/* Растущий байтовый буфер: входной и выходной буферы соединения,
 * сборка записи перед отправкой на диск. */
#ifndef NESTOR_UTIL_BUF_H
#define NESTOR_UTIL_BUF_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <nestor/status.h>
#include "util/compiler.h"
#include "util/slice.h"

typedef struct nst_buf {
    uint8_t *data;
    size_t len;
    size_t cap;
    size_t read_pos;  /* потреблённый префикс (для сетевых буферов) */
} nst_buf;

void nst_buf_init(nst_buf *b);
void nst_buf_free(nst_buf *b);

[[nodiscard]] nst_status nst_buf_reserve(nst_buf *b, size_t extra);
[[nodiscard]] nst_status nst_buf_append(nst_buf *b, const void *p, size_t n);
[[nodiscard]] nst_status nst_buf_append_slice(nst_buf *b, nst_slice s);
[[nodiscard]] nst_status nst_buf_append_byte(nst_buf *b, uint8_t byte);
[[nodiscard]] NST_PRINTF(2, 3) nst_status nst_buf_printf(nst_buf *b, const char *fmt, ...);

/* Непрочитанная часть. */
static inline nst_slice nst_buf_pending(const nst_buf *b) {
    return (nst_slice){ .ptr = b->data + b->read_pos, .len = b->len - b->read_pos };
}
static inline size_t nst_buf_pending_len(const nst_buf *b) { return b->len - b->read_pos; }

void nst_buf_consume(nst_buf *b, size_t n);
/* Сдвинуть непрочитанный хвост в начало, освободив префикс. */
void nst_buf_compact(nst_buf *b);
void nst_buf_clear(nst_buf *b);

#endif /* NESTOR_UTIL_BUF_H */
