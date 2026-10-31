/* Состояние одного клиентского соединения. */
#ifndef NESTOR_NET_CONN_H
#define NESTOR_NET_CONN_H

#include <stdbool.h>
#include <stdint.h>

#include "util/buf.h"

typedef struct nst_conn {
    int fd;
    bool want_write;   /* в epoll зарегистрирован EPOLLOUT */
    bool closing;      /* дописать выходной буфер и закрыть */
    uint64_t last_active_ms;
    uint64_t commands;
    nst_buf in;
    nst_buf out;
    char peer[64];
} nst_conn;

void nst_conn_init(nst_conn *c, int fd, const char *peer);
void nst_conn_free(nst_conn *c);

#endif /* NESTOR_NET_CONN_H */
