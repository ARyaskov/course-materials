#include "util/buf.h"

#include <stdarg.h>
#include <stdckdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

constexpr size_t NST_BUF_MIN_CAP = 256;

void nst_buf_init(nst_buf *b) { *b = (nst_buf){}; }

void nst_buf_free(nst_buf *b) {
    free(b->data);
    *b = (nst_buf){};
}

nst_status nst_buf_reserve(nst_buf *b, size_t extra) {
    size_t need;
    if (ckd_add(&need, b->len, extra)) return NST_E_TOOBIG;
    if (need <= b->cap) return NST_OK;

    size_t cap = b->cap ? b->cap : NST_BUF_MIN_CAP;
    while (cap < need) {
        size_t next;
        if (ckd_add(&next, cap, cap / 2)) return NST_E_TOOBIG;
        cap = next;
    }
    /* Классическая ошибка — b->data = realloc(b->data, cap): при неудаче
     * старый указатель теряется. Поэтому через временную переменную. */
    uint8_t *tmp = realloc(b->data, cap);
    if (tmp == nullptr) return NST_E_NOMEM;
    b->data = tmp;
    b->cap = cap;
    return NST_OK;
}

nst_status nst_buf_append(nst_buf *b, const void *p, size_t n) {
    if (n == 0) return NST_OK;
    NST_TRY(nst_buf_reserve(b, n));
    memcpy(b->data + b->len, p, n);
    b->len += n;
    return NST_OK;
}

nst_status nst_buf_append_slice(nst_buf *b, nst_slice s) {
    return nst_buf_append(b, s.ptr, s.len);
}

nst_status nst_buf_append_byte(nst_buf *b, uint8_t byte) {
    NST_TRY(nst_buf_reserve(b, 1));
    b->data[b->len++] = byte;
    return NST_OK;
}

nst_status nst_buf_printf(nst_buf *b, const char *fmt, ...) {
    va_list ap;
    va_start(ap);
    va_list ap2;
    va_copy(ap2, ap);
    int need = vsnprintf(nullptr, 0, fmt, ap);
    va_end(ap);
    if (need < 0) { va_end(ap2); return NST_E_INVAL; }

    nst_status st = nst_buf_reserve(b, (size_t)need + 1);
    if (st != NST_OK) { va_end(ap2); return st; }
    vsnprintf((char *)b->data + b->len, (size_t)need + 1, fmt, ap2);
    va_end(ap2);
    b->len += (size_t)need; /* завершающий нуль в длину не входит */
    return NST_OK;
}

void nst_buf_consume(nst_buf *b, size_t n) {
    size_t avail = b->len - b->read_pos;
    b->read_pos += n < avail ? n : avail;
    if (b->read_pos == b->len) { b->read_pos = 0; b->len = 0; }
}

void nst_buf_compact(nst_buf *b) {
    if (b->read_pos == 0) return;
    size_t rest = b->len - b->read_pos;
    if (rest > 0) memmove(b->data, b->data + b->read_pos, rest);
    b->len = rest;
    b->read_pos = 0;
}

void nst_buf_clear(nst_buf *b) { b->len = 0; b->read_pos = 0; }
