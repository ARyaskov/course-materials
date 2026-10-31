#include "store/record.h"

#include <stdckdint.h>
#include <string.h>

#include "util/compiler.h"
#include "util/crc32c.h"
#include "util/endian.h"

bool nst_record_size(size_t key_len, size_t value_len, size_t *out) {
    size_t body;
    if (ckd_add(&body, key_len, value_len)) return false;
    size_t total;
    if (ckd_add(&total, body, NST_REC_HDR_SIZE)) return false;
    *out = total;
    return true;
}

nst_status nst_record_encode(const nst_record *rec, uint8_t *dst, size_t cap,
                             size_t *written) {
    if (rec->key.len == 0 || rec->key.len > NST_MAX_KEY_BYTES) return NST_E_INVAL;
    if (rec->value.len > NST_MAX_VALUE_BYTES) return NST_E_TOOBIG;

    size_t total;
    if (!nst_record_size(rec->key.len, rec->value.len, &total)) return NST_E_TOOBIG;
    if (total > cap) return NST_E_TOOBIG;

    dst[4] = rec->flags;
    dst[5] = 0;
    nst_store_le16(dst + 6, (uint16_t)rec->key.len);
    nst_store_le32(dst + 8, (uint32_t)rec->value.len);
    nst_store_le64(dst + 12, rec->seq);
    nst_store_le64(dst + 20, rec->timestamp_ms);
    memcpy(dst + NST_REC_HDR_SIZE, rec->key.ptr, rec->key.len);
    if (rec->value.len > 0)
        memcpy(dst + NST_REC_HDR_SIZE + rec->key.len, rec->value.ptr, rec->value.len);

    uint32_t crc = nst_crc32c(0, dst + 4, total - 4);
    nst_store_le32(dst, crc);

    *written = total;
    return NST_OK;
}

nst_status nst_record_peek_header(const uint8_t hdr[static NST_REC_HDR_SIZE],
                                  uint32_t *key_len, uint32_t *value_len,
                                  uint64_t *seq, uint8_t *flags) {
    uint8_t f = hdr[4];
    uint32_t klen = nst_load_le16(hdr + 6);
    uint32_t vlen = nst_load_le32(hdr + 8);

    if (hdr[5] != 0) return NST_E_CORRUPT;
    if (klen == 0 || klen > NST_MAX_KEY_BYTES) return NST_E_CORRUPT;
    if (vlen > NST_MAX_VALUE_BYTES) return NST_E_CORRUPT;
    if ((f & ~(uint8_t)NST_REC_TOMBSTONE) != 0) return NST_E_CORRUPT;
    if ((f & NST_REC_TOMBSTONE) && vlen != 0) return NST_E_CORRUPT;

    if (key_len) *key_len = klen;
    if (value_len) *value_len = vlen;
    if (seq) *seq = nst_load_le64(hdr + 12);
    if (flags) *flags = f;
    return NST_OK;
}

nst_status nst_record_decode(const uint8_t *src, size_t len, nst_record *out,
                             size_t *consumed) {
    if (len < NST_REC_HDR_SIZE) return NST_E_CORRUPT;

    uint32_t klen, vlen;
    uint64_t seq;
    uint8_t flags;
    NST_TRY(nst_record_peek_header(src, &klen, &vlen, &seq, &flags));

    size_t total;
    if (!nst_record_size(klen, vlen, &total)) return NST_E_CORRUPT;
    if (total > len) return NST_E_CORRUPT;

    uint32_t stored = nst_load_le32(src);
    uint32_t actual = nst_crc32c(0, src + 4, total - 4);
    if (stored != actual) return NST_E_CORRUPT;

    *out = (nst_record){
        .key = { .ptr = src + NST_REC_HDR_SIZE, .len = klen },
        .value = { .ptr = src + NST_REC_HDR_SIZE + klen, .len = vlen },
        .seq = seq,
        .timestamp_ms = nst_load_le64(src + 20),
        .flags = flags,
    };
    if (consumed) *consumed = total;
    return NST_OK;
}
