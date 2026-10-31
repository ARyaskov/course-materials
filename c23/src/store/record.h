/* Кодирование и декодирование записи лога. */
#ifndef NESTOR_STORE_RECORD_H
#define NESTOR_STORE_RECORD_H

#include <stdbool.h>
#include <stdint.h>

#include <nestor/status.h>
#include "store/format.h"
#include "util/slice.h"

typedef struct nst_record {
    nst_slice key;
    nst_slice value;
    uint64_t seq;
    uint64_t timestamp_ms;
    uint8_t flags;
} nst_record;

static inline bool nst_record_is_tombstone(const nst_record *r) {
    return (r->flags & NST_REC_TOMBSTONE) != 0;
}

/* Полный размер записи на диске. false при переполнении size_t. */
[[nodiscard]] bool nst_record_size(size_t key_len, size_t value_len, size_t *out);

/* Записать rec в буфер размера cap. Возвращает NST_E_TOOBIG, если не влезает. */
[[nodiscard]] nst_status nst_record_encode(const nst_record *rec, uint8_t *dst,
                                           size_t cap, size_t *written);

/* Разобрать запись из буфера. Ключ и значение указывают внутрь src —
 * копий не делается. Проверяется CRC и согласованность длин. */
[[nodiscard]] nst_status nst_record_decode(const uint8_t *src, size_t len,
                                           nst_record *out, size_t *consumed);

/* Разобрать только заголовок: длины и seq, без проверки CRC тела.
 * Нужно при сканировании файла, когда тело ещё не прочитано. */
[[nodiscard]] nst_status nst_record_peek_header(const uint8_t hdr[static NST_REC_HDR_SIZE],
                                                uint32_t *key_len, uint32_t *value_len,
                                                uint64_t *seq, uint8_t *flags);

#endif /* NESTOR_STORE_RECORD_H */
