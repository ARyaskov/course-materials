/* nestor-cli — клиент протокола nestor. */
#define _GNU_SOURCE
#include <errno.h>
#include <netdb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include <nestor/status.h>

#include "util/buf.h"
#include "util/io.h"

static int connect_tcp(const char *host, const char *port) {
    struct addrinfo hints = { .ai_family = AF_UNSPEC, .ai_socktype = SOCK_STREAM };
    struct addrinfo *res = nullptr;
    int rc = getaddrinfo(host, port, &hints, &res);
    if (rc != 0) { fprintf(stderr, "getaddrinfo: %s\n", gai_strerror(rc)); return -1; }

    int fd = -1;
    for (struct addrinfo *ai = res; ai != nullptr; ai = ai->ai_next) {
        fd = socket(ai->ai_family, ai->ai_socktype | SOCK_CLOEXEC, ai->ai_protocol);
        if (fd < 0) continue;
        if (connect(fd, ai->ai_addr, ai->ai_addrlen) == 0) break;
        nst_close_fd(&fd);
    }
    freeaddrinfo(res);
    if (fd < 0) fprintf(stderr, "не удалось подключиться к %s:%s\n", host, port);
    return fd;
}

static int connect_unix(const char *path) {
    struct sockaddr_un addr = { .sun_family = AF_UNIX };
    if (strlen(path) >= sizeof addr.sun_path) return -1;
    memcpy(addr.sun_path, path, strlen(path));
    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) return -1;
    if (connect(fd, (struct sockaddr *)&addr, sizeof addr) != 0) {
        perror("connect");
        nst_close_fd(&fd);
        return -1;
    }
    return fd;
}

/* Прочитать ответ целиком: одна строка, а для $<len> — ещё len+2 байта. */
static int read_reply(int fd, nst_buf *buf) {
    for (;;) {
        nst_slice p = nst_buf_pending(buf);
        size_t nl = nst_slice_find_byte(p, '\n');
        if (nl != SIZE_MAX) {
            if (p.ptr[0] != '$') return 0;
            long len = strtol((const char *)p.ptr + 1, nullptr, 10);
            if (len < 0) return 0;
            size_t need = nl + 1 + (size_t)len + 2;
            if (p.len >= need) return 0;
        }
        if (nst_buf_reserve(buf, 4096) != NST_OK) return -1;
        ssize_t n = read(fd, buf->data + buf->len, 4096);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return -1;
        buf->len += (size_t)n;
    }
}

static void print_reply(const nst_buf *buf) {
    nst_slice p = nst_buf_pending(buf);
    if (p.len == 0) return;
    size_t nl = nst_slice_find_byte(p, '\n');
    if (nl == SIZE_MAX) return;

    if (p.ptr[0] == '$') {
        long len = strtol((const char *)p.ptr + 1, nullptr, 10);
        if (len < 0) { puts("(nil)"); return; }
        fwrite(p.ptr + nl + 1, 1, (size_t)len, stdout);
        fputc('\n', stdout);
    } else {
        fwrite(p.ptr, 1, nl > 0 && p.ptr[nl - 1] == '\r' ? nl - 1 : nl, stdout);
        fputc('\n', stdout);
    }
}

[[noreturn]] static void usage(int code) {
    fprintf(code == 0 ? stdout : stderr,
        "nestor-cli — клиент nestor\n\n"
        "  nestor-cli [--host H] [--port P] [--unix PATH] КОМАНДА\n\n"
        "Команды:\n"
        "  put KEY VALUE\n  get KEY\n  del KEY\n  ping\n  stats\n");
    exit(code);
}

int main(int argc, char **argv) {
    const char *host = "127.0.0.1", *port = "7717", *unix_path = nullptr;
    int i = 1;
    for (; i < argc; i++) {
        if (strcmp(argv[i], "--host") == 0 && i + 1 < argc) host = argv[++i];
        else if (strcmp(argv[i], "--port") == 0 && i + 1 < argc) port = argv[++i];
        else if (strcmp(argv[i], "--unix") == 0 && i + 1 < argc) unix_path = argv[++i];
        else if (strcmp(argv[i], "--help") == 0) usage(0);
        else break;
    }
    if (i >= argc) usage(2);

    const char *cmd = argv[i++];
    nst_buf req;
    nst_buf_init(&req);
    nst_status st = NST_OK;

    if (strcmp(cmd, "ping") == 0)       st = nst_buf_printf(&req, "PING\r\n");
    else if (strcmp(cmd, "stats") == 0) st = nst_buf_printf(&req, "STATS\r\n");
    else if (strcmp(cmd, "get") == 0 || strcmp(cmd, "del") == 0) {
        if (i >= argc) usage(2);
        size_t klen = strlen(argv[i]);
        st = nst_buf_printf(&req, "%s %zu\r\n", cmd[0] == 'g' ? "GET" : "DEL", klen);
        if (st == NST_OK) st = nst_buf_append(&req, argv[i], klen);
        if (st == NST_OK) st = nst_buf_append(&req, "\r\n", 2);
    } else if (strcmp(cmd, "put") == 0) {
        if (i + 1 >= argc) usage(2);
        size_t klen = strlen(argv[i]), vlen = strlen(argv[i + 1]);
        st = nst_buf_printf(&req, "PUT %zu %zu\r\n", klen, vlen);
        if (st == NST_OK) st = nst_buf_append(&req, argv[i], klen);
        if (st == NST_OK) st = nst_buf_append(&req, argv[i + 1], vlen);
        if (st == NST_OK) st = nst_buf_append(&req, "\r\n", 2);
    } else usage(2);

    if (st != NST_OK) { fprintf(stderr, "ошибка: %s\n", nst_status_str(st)); return 1; }

    int fd = unix_path ? connect_unix(unix_path) : connect_tcp(host, port);
    if (fd < 0) { nst_buf_free(&req); return 1; }

    int rc = 0;
    if (nst_write_full(fd, req.data, req.len) != NST_OK) {
        perror("write");
        rc = 1;
    } else {
        nst_buf reply;
        nst_buf_init(&reply);
        if (read_reply(fd, &reply) == 0) print_reply(&reply);
        else { fprintf(stderr, "нет ответа\n"); rc = 1; }
        nst_buf_free(&reply);
    }
    nst_close_fd(&fd);
    nst_buf_free(&req);
    return rc;
}
