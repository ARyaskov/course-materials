/* Явное кодирование чисел в little-endian.
 * Формат файла не зависит от порядка байтов машины; memcpy не нарушает
 * строгий алиасинг и на -O2 схлопывается в одну инструкцию. */
#ifndef NESTOR_UTIL_ENDIAN_H
#define NESTOR_UTIL_ENDIAN_H

#include <stdint.h>
#include <string.h>

static inline uint16_t nst_bswap16(uint16_t v) { return (uint16_t)((v << 8) | (v >> 8)); }
static inline uint32_t nst_bswap32(uint32_t v) { return __builtin_bswap32(v); }
static inline uint64_t nst_bswap64(uint64_t v) { return __builtin_bswap64(v); }

#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
#  define NST_TO_LE16(v) (v)
#  define NST_TO_LE32(v) (v)
#  define NST_TO_LE64(v) (v)
#elif __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
#  define NST_TO_LE16(v) nst_bswap16(v)
#  define NST_TO_LE32(v) nst_bswap32(v)
#  define NST_TO_LE64(v) nst_bswap64(v)
#else
#  error "неизвестный порядок байтов"
#endif

static inline void nst_store_le16(void *dst, uint16_t v) {
    uint16_t le = NST_TO_LE16(v); memcpy(dst, &le, sizeof le);
}
static inline void nst_store_le32(void *dst, uint32_t v) {
    uint32_t le = NST_TO_LE32(v); memcpy(dst, &le, sizeof le);
}
static inline void nst_store_le64(void *dst, uint64_t v) {
    uint64_t le = NST_TO_LE64(v); memcpy(dst, &le, sizeof le);
}
static inline uint16_t nst_load_le16(const void *src) {
    uint16_t le; memcpy(&le, src, sizeof le); return NST_TO_LE16(le);
}
static inline uint32_t nst_load_le32(const void *src) {
    uint32_t le; memcpy(&le, src, sizeof le); return NST_TO_LE32(le);
}
static inline uint64_t nst_load_le64(const void *src) {
    uint64_t le; memcpy(&le, src, sizeof le); return NST_TO_LE64(le);
}

#endif /* NESTOR_UTIL_ENDIAN_H */
