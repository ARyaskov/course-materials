#include "net/conn.h"

#include <stdio.h>
#include <string.h>

#include "util/clock.h"

void nst_conn_init(nst_conn *c, int fd, const char *peer) {
    *c = (nst_conn){ .fd = fd, .last_active_ms = nst_now_wall_ms() };
    nst_buf_init(&c->in);
    nst_buf_init(&c->out);
    snprintf(c->peer, sizeof c->peer, "%s", peer ? peer : "?");
}

void nst_conn_free(nst_conn *c) {
    nst_buf_free(&c->in);
    nst_buf_free(&c->out);
    c->fd = -1;
}
