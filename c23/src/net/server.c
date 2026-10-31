#define _GNU_SOURCE
#include "net/server.h"

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/signalfd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include "net/conn.h"
#include "store/format.h"
#include "net/proto.h"
#include "util/clock.h"
#include "util/compiler.h"
#include "util/io.h"
#include "util/log.h"

constexpr uint16_t NST_DEFAULT_PORT = 7717;
constexpr size_t NST_READ_CHUNK = 64 * 1024;

/* Тип дескриптора, лежащего в epoll: сохраняем его рядом с указателем,
 * чтобы не заводить отдельные таблицы. */
typedef enum ev_kind : uint8_t { EV_LISTEN, EV_SIGNAL, EV_CONN } ev_kind;

typedef struct ev_slot {
    ev_kind kind;
    int fd;
    nst_conn conn;
} ev_slot;

struct nst_server {
    nst_db *db;
    nst_server_config cfg;
    int epfd;
    int sig_fd;
    int tcp_fd;
    int unix_fd;
    uint16_t port;
    uint32_t conn_count;
    bool stopping;
    ev_slot listen_tcp, listen_unix, signal_slot;
    uint64_t total_connections;
    uint64_t total_commands;
};

/* ------------------------------------------------------------------ */

static nst_status set_nonblocking(int fd) {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0) return nst_status_from_errno(errno);
    if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) != 0) return nst_status_from_errno(errno);
    return NST_OK;
}

static nst_status listen_tcp(const char *host, uint16_t port, int *out_fd,
                             uint16_t *out_port) {
    char port_str[8];
    snprintf(port_str, sizeof port_str, "%u", (unsigned)port);

    struct addrinfo hints = {
        .ai_family = AF_UNSPEC,
        .ai_socktype = SOCK_STREAM,
        .ai_flags = AI_PASSIVE,
    };
    struct addrinfo *res = nullptr;
    int rc = getaddrinfo(host, port_str, &hints, &res);
    if (rc != 0) {
        NST_LOGE("getaddrinfo(%s:%u): %s", host ? host : "*", port, gai_strerror(rc));
        return NST_E_INVAL;
    }

    nst_status st = NST_E_IO;
    int fd = -1;
    for (struct addrinfo *ai = res; ai != nullptr; ai = ai->ai_next) {
        fd = socket(ai->ai_family, ai->ai_socktype | SOCK_CLOEXEC, ai->ai_protocol);
        if (fd < 0) continue;

        int one = 1;
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
        if (ai->ai_family == AF_INET6)
            setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &(int){0}, sizeof(int));

        if (bind(fd, ai->ai_addr, ai->ai_addrlen) == 0 && listen(fd, 512) == 0) {
            st = NST_OK;
            break;
        }
        st = nst_status_from_errno(errno);
        nst_close_fd(&fd);
    }
    freeaddrinfo(res);
    if (st != NST_OK) return st;

    struct sockaddr_storage ss;
    socklen_t slen = sizeof ss;
    uint16_t actual = port;
    if (getsockname(fd, (struct sockaddr *)&ss, &slen) == 0) {
        if (ss.ss_family == AF_INET)
            actual = ntohs(((struct sockaddr_in *)&ss)->sin_port);
        else if (ss.ss_family == AF_INET6)
            actual = ntohs(((struct sockaddr_in6 *)&ss)->sin6_port);
    }

    st = set_nonblocking(fd);
    if (st != NST_OK) { nst_close_fd(&fd); return st; }

    *out_fd = fd;
    if (out_port) *out_port = actual;
    return NST_OK;
}

static nst_status listen_unix(const char *path, int *out_fd) {
    struct sockaddr_un addr = { .sun_family = AF_UNIX };
    if (strlen(path) >= sizeof addr.sun_path) return NST_E_INVAL;
    memcpy(addr.sun_path, path, strlen(path));

    (void)unlink(path);   /* остаток от прошлого запуска */
    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) return nst_status_from_errno(errno);

    if (bind(fd, (struct sockaddr *)&addr, sizeof addr) != 0 || listen(fd, 512) != 0) {
        nst_status st = nst_status_from_errno(errno);
        nst_close_fd(&fd);
        return st;
    }
    nst_status st = set_nonblocking(fd);
    if (st != NST_OK) { nst_close_fd(&fd); return st; }
    *out_fd = fd;
    return NST_OK;
}

static void shutdown_signal_set(sigset_t *mask) {
    sigemptyset(mask);
    sigaddset(mask, SIGINT);
    sigaddset(mask, SIGTERM);
}

nst_status nst_server_block_signals(void) {
    sigset_t mask;
    shutdown_signal_set(&mask);
    if (pthread_sigmask(SIG_BLOCK, &mask, nullptr) != 0) return NST_E_IO;
    return NST_OK;
}

/* Сигналы приходят как обычные события epoll: обработчик сигнала не нужен,
 * а значит не нужны и ограничения async-signal-safe функций. */
static nst_status setup_signalfd(int *out_fd) {
    sigset_t mask;
    shutdown_signal_set(&mask);
    NST_TRY(nst_server_block_signals());

    int fd = signalfd(-1, &mask, SFD_NONBLOCK | SFD_CLOEXEC);
    if (fd < 0) return nst_status_from_errno(errno);
    *out_fd = fd;
    return NST_OK;
}

static nst_status epoll_add(int epfd, int fd, uint32_t events, void *ptr) {
    struct epoll_event ev = { .events = events, .data.ptr = ptr };
    if (epoll_ctl(epfd, EPOLL_CTL_ADD, fd, &ev) != 0) return nst_status_from_errno(errno);
    return NST_OK;
}

static void epoll_update(int epfd, int fd, uint32_t events, void *ptr) {
    struct epoll_event ev = { .events = events, .data.ptr = ptr };
    (void)epoll_ctl(epfd, EPOLL_CTL_MOD, fd, &ev);
}

/* ------------------------------------------------------------------ */

nst_status nst_server_create(nst_db *db, const nst_server_config *cfg, nst_server **out) {
    if (db == nullptr || out == nullptr) return NST_E_INVAL;

    nst_server *srv = calloc(1, sizeof *srv);
    if (srv == nullptr) return NST_E_NOMEM;
    srv->db = db;
    srv->epfd = srv->sig_fd = srv->tcp_fd = srv->unix_fd = -1;
    srv->cfg = cfg ? *cfg : (nst_server_config){};
    if (srv->cfg.port == 0 && cfg == nullptr) srv->cfg.port = NST_DEFAULT_PORT;
    if (srv->cfg.max_connections == 0) srv->cfg.max_connections = 1024;
    if (srv->cfg.max_out_buffer == 0) srv->cfg.max_out_buffer = 8u << 20;

    nst_status st = NST_OK;
    srv->epfd = epoll_create1(EPOLL_CLOEXEC);
    if (srv->epfd < 0) { st = nst_status_from_errno(errno); goto fail; }

    NST_TRY_GOTO(listen_tcp(srv->cfg.host, srv->cfg.port, &srv->tcp_fd, &srv->port), fail);
    srv->listen_tcp = (ev_slot){ .kind = EV_LISTEN, .fd = srv->tcp_fd };
    NST_TRY_GOTO(epoll_add(srv->epfd, srv->tcp_fd, EPOLLIN, &srv->listen_tcp), fail);

    if (srv->cfg.unix_path != nullptr) {
        NST_TRY_GOTO(listen_unix(srv->cfg.unix_path, &srv->unix_fd), fail);
        srv->listen_unix = (ev_slot){ .kind = EV_LISTEN, .fd = srv->unix_fd };
        NST_TRY_GOTO(epoll_add(srv->epfd, srv->unix_fd, EPOLLIN, &srv->listen_unix), fail);
    }

    NST_TRY_GOTO(setup_signalfd(&srv->sig_fd), fail);
    srv->signal_slot = (ev_slot){ .kind = EV_SIGNAL, .fd = srv->sig_fd };
    NST_TRY_GOTO(epoll_add(srv->epfd, srv->sig_fd, EPOLLIN, &srv->signal_slot), fail);

    NST_LOGI("listening on port %u%s%s", srv->port,
             srv->cfg.unix_path ? " and unix socket " : "",
             srv->cfg.unix_path ? srv->cfg.unix_path : "");
    *out = srv;
    return NST_OK;

fail:
    nst_server_destroy(srv);
    return st;
}

void nst_server_destroy(nst_server *srv) {
    if (srv == nullptr) return;
    nst_close_fd(&srv->sig_fd);
    nst_close_fd(&srv->tcp_fd);
    if (srv->unix_fd >= 0) {
        nst_close_fd(&srv->unix_fd);
        if (srv->cfg.unix_path) (void)unlink(srv->cfg.unix_path);
    }
    nst_close_fd(&srv->epfd);
    free(srv);
}

uint16_t nst_server_port(const nst_server *srv) { return srv ? srv->port : 0; }

/* ------------------------------------------------------------------ */
/* Обработка соединений                                                */

static void conn_close(nst_server *srv, ev_slot *slot) {
    epoll_ctl(srv->epfd, EPOLL_CTL_DEL, slot->conn.fd, nullptr);
    nst_close_fd(&slot->conn.fd);
    nst_conn_free(&slot->conn);
    free(slot);
    srv->conn_count--;
}

static void conn_arm(nst_server *srv, ev_slot *slot) {
    bool want_write = nst_buf_pending_len(&slot->conn.out) > 0;
    if (want_write == slot->conn.want_write) return;
    slot->conn.want_write = want_write;
    epoll_update(srv->epfd, slot->conn.fd,
                 EPOLLIN | (want_write ? (uint32_t)EPOLLOUT : 0u), slot);
}

static nst_status handle_stats(nst_server *srv, nst_buf *out) {
    nst_stats s;
    nst_get_stats(srv->db, &s);

    nst_buf body;
    nst_buf_init(&body);
    nst_status st = nst_buf_printf(&body,
        "keys %" PRIu64 "\n"
        "segments %" PRIu64 "\n"
        "live_bytes %" PRIu64 "\n"
        "total_bytes %" PRIu64 "\n"
        "puts %" PRIu64 "\n"
        "gets %" PRIu64 "\n"
        "deletes %" PRIu64 "\n"
        "get_misses %" PRIu64 "\n"
        "compactions %" PRIu64 "\n"
        "reclaimed_bytes %" PRIu64 "\n"
        "fsyncs %" PRIu64 "\n"
        "connections %" PRIu64 "\n"
        "commands %" PRIu64 "\n"
        "version %s\n",
        s.keys, s.segments, s.live_bytes, s.total_bytes, s.puts, s.gets,
        s.deletes, s.get_misses, s.compactions, s.reclaimed_bytes, s.fsyncs,
        srv->total_connections, srv->total_commands, nst_version());
    if (st == NST_OK)
        st = nst_proto_reply_value(out, (nst_slice){ .ptr = body.data, .len = body.len });
    nst_buf_free(&body);
    return st;
}

/* Выполнить одну команду. Возвращает false, если соединение надо закрыть. */
static bool execute(nst_server *srv, nst_conn *c, const nst_command *cmd) {
    nst_status st = NST_OK;
    srv->total_commands++;
    c->commands++;

    switch (cmd->kind) {
        case NST_CMD_PING:
            st = nst_proto_reply_pong(&c->out);
            break;

        case NST_CMD_STATS:
            st = handle_stats(srv, &c->out);
            break;

        case NST_CMD_GET: {
            nst_slice value;
            nst_status get_st = nst_get(srv->db, cmd->key, &value);
            if (get_st == NST_OK) {
                st = nst_proto_reply_value(&c->out, value);
                nst_free_value(value);
            } else if (get_st == NST_E_NOTFOUND) {
                st = nst_proto_reply_nil(&c->out);
            } else {
                st = nst_proto_reply_error(&c->out, nst_status_str(get_st));
            }
            break;
        }

        case NST_CMD_PUT: {
            nst_status put_st = nst_put(srv->db, cmd->key, cmd->value);
            st = (put_st == NST_OK) ? nst_proto_reply_ok(&c->out)
                                    : nst_proto_reply_error(&c->out, nst_status_str(put_st));
            break;
        }

        case NST_CMD_DEL: {
            nst_status del_st = nst_delete(srv->db, cmd->key);
            if (del_st == NST_OK) st = nst_proto_reply_ok(&c->out);
            else if (del_st == NST_E_NOTFOUND) st = nst_proto_reply_nil(&c->out);
            else st = nst_proto_reply_error(&c->out, nst_status_str(del_st));
            break;
        }

        case NST_CMD_QUIT:
            st = nst_proto_reply_ok(&c->out);
            c->closing = true;
            break;

        case NST_CMD_NONE:
            unreachable();
    }
    return st == NST_OK;
}

/* Разбор всего, что накопилось во входном буфере: конвейеризация
 * получается бесплатно — клиент может слать команды пачкой. */
static bool drain_input(nst_server *srv, nst_conn *c) {
    nst_proto_limits lim = {
        .max_key_bytes = NST_MAX_KEY_BYTES,
        .max_value_bytes = 16u << 20,
    };

    for (;;) {
        if (c->closing) break;
        nst_command cmd;
        size_t consumed = 0;
        nst_status st = nst_proto_parse(&c->in, lim, &cmd, &consumed);

        if (st == NST_E_AGAIN) break;
        if (st != NST_OK) {
            (void)nst_proto_reply_error(&c->out, nst_status_str(st));
            c->closing = true;
            break;
        }
        if (!execute(srv, c, &cmd)) return false;
        nst_buf_consume(&c->in, consumed);

        if (nst_buf_pending_len(&c->out) > srv->cfg.max_out_buffer) {
            NST_LOGW("%s: output buffer over limit, closing", c->peer);
            return false;
        }
    }
    nst_buf_compact(&c->in);
    return true;
}

static bool conn_read(nst_server *srv, nst_conn *c) {
    for (;;) {
        if (nst_buf_reserve(&c->in, NST_READ_CHUNK) != NST_OK) return false;
        ssize_t n = read(c->fd, c->in.data + c->in.len, NST_READ_CHUNK);
        if (n > 0) {
            c->in.len += (size_t)n;
            c->last_active_ms = nst_now_wall_ms();
            if (!drain_input(srv, c)) return false;
            if ((size_t)n < NST_READ_CHUNK) return true;  /* сокет опустел */
            continue;
        }
        if (n == 0) return false;                          /* клиент закрыл */
        if (errno == EINTR) continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK) return true;
        return false;
    }
}

static bool conn_write(nst_conn *c) {
    while (nst_buf_pending_len(&c->out) > 0) {
        nst_slice p = nst_buf_pending(&c->out);
        ssize_t n = write(c->fd, p.ptr, p.len);
        if (n > 0) { nst_buf_consume(&c->out, (size_t)n); continue; }
        if (n < 0 && errno == EINTR) continue;
        if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) return true;
        return false;
    }
    nst_buf_compact(&c->out);
    return !c->closing;
}

static void accept_all(nst_server *srv, int listen_fd) {
    for (;;) {
        struct sockaddr_storage ss;
        socklen_t slen = sizeof ss;
        int fd = accept4(listen_fd, (struct sockaddr *)&ss, &slen,
                         SOCK_NONBLOCK | SOCK_CLOEXEC);
        if (fd < 0) {
            if (errno == EINTR) continue;
            if (errno == EAGAIN || errno == EWOULDBLOCK) return;
            /* EMFILE: дескрипторы кончились — не крутим цикл впустую. */
            NST_LOGW("accept: %s", strerror(errno));
            return;
        }
        if (srv->conn_count >= srv->cfg.max_connections) {
            NST_LOGW("connection limit %u reached, rejecting", srv->cfg.max_connections);
            nst_close_fd(&fd);
            continue;
        }

        char peer[64] = "unix";
        if (ss.ss_family == AF_INET || ss.ss_family == AF_INET6) {
            char host[NI_MAXHOST], port[NI_MAXSERV];
            if (getnameinfo((struct sockaddr *)&ss, slen, host, sizeof host,
                            port, sizeof port, NI_NUMERICHOST | NI_NUMERICSERV) == 0)
                snprintf(peer, sizeof peer, "%.46s:%.7s", host, port);
            setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &(int){1}, sizeof(int));
        }

        ev_slot *slot = calloc(1, sizeof *slot);
        if (slot == nullptr) { nst_close_fd(&fd); continue; }
        slot->kind = EV_CONN;
        slot->fd = fd;
        nst_conn_init(&slot->conn, fd, peer);

        if (epoll_add(srv->epfd, fd, EPOLLIN, slot) != NST_OK) {
            nst_conn_free(&slot->conn);
            nst_close_fd(&fd);
            free(slot);
            continue;
        }
        srv->conn_count++;
        srv->total_connections++;
        NST_LOGD("accepted %s (%u active)", peer, srv->conn_count);
    }
}

nst_status nst_server_run(nst_server *srv) {
    constexpr int MAX_EVENTS = 256;
    struct epoll_event events[MAX_EVENTS];

    while (!srv->stopping || srv->conn_count > 0) {
        int n = epoll_wait(srv->epfd, events, MAX_EVENTS, 1000);
        if (n < 0) {
            if (errno == EINTR) continue;
            return nst_status_from_errno(errno);
        }

        for (int i = 0; i < n; i++) {
            ev_slot *slot = events[i].data.ptr;
            uint32_t ev = events[i].events;

            switch (slot->kind) {
                case EV_LISTEN:
                    if (!srv->stopping) accept_all(srv, slot->fd);
                    break;

                case EV_SIGNAL: {
                    struct signalfd_siginfo si;
                    while (read(srv->sig_fd, &si, sizeof si) == (ssize_t)sizeof si)
                        NST_LOGI("signal %u received, shutting down", si.ssi_signo);
                    srv->stopping = true;
                    /* Перестаём принимать новых клиентов, но даём текущим
                     * дописать ответы. */
                    epoll_ctl(srv->epfd, EPOLL_CTL_DEL, srv->tcp_fd, nullptr);
                    if (srv->unix_fd >= 0)
                        epoll_ctl(srv->epfd, EPOLL_CTL_DEL, srv->unix_fd, nullptr);
                    break;
                }

                case EV_CONN: {
                    nst_conn *c = &slot->conn;
                    bool alive = true;
                    if (ev & (EPOLLHUP | EPOLLERR)) alive = false;
                    if (alive && (ev & EPOLLIN)) alive = conn_read(srv, c);
                    if (alive && nst_buf_pending_len(&c->out) > 0) alive = conn_write(c);
                    if (alive) conn_arm(srv, slot);
                    else conn_close(srv, slot);
                    break;
                }
            }
        }

        if (srv->stopping && srv->conn_count == 0) break;
    }

    NST_LOGI("event loop finished, %" PRIu64 " commands served", srv->total_commands);
    return NST_OK;
}
