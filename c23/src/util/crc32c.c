#include "util/crc32c.h"

#include "util/compiler.h"

#if defined(__x86_64__) && defined(__has_include)
#  if __has_include(<nmmintrin.h>)
#    include <nmmintrin.h>
#    define NST_CRC32C_X86 1
#  endif
#endif

/* Табличная реализация — переносимый запасной путь. Таблица строится
 * один раз при первом обращении: 1 КиБ данных против 1 КиБ кода
 * генератора, зато нет магической константы в исходнике. */
static uint32_t g_table[256];
static bool g_table_ready = false;

static void build_table(void) {
    constexpr uint32_t poly = 0x82F6'3B78u; /* отражённый 0x1EDC6F41 */
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t crc = i;
        for (int k = 0; k < 8; k++)
            crc = (crc & 1u) ? (crc >> 1) ^ poly : (crc >> 1);
        g_table[i] = crc;
    }
    g_table_ready = true;
}

static uint32_t crc32c_table(uint32_t crc, const unsigned char *p, size_t len) {
    if (!g_table_ready) build_table();
    crc = ~crc;
    for (size_t i = 0; i < len; i++)
        crc = g_table[(crc ^ p[i]) & 0xFFu] ^ (crc >> 8);
    return ~crc;
}

#if defined(NST_CRC32C_X86)
static bool have_sse42(void) {
    static int cached = -1;
    if (cached < 0) cached = __builtin_cpu_supports("sse4.2") ? 1 : 0;
    return cached == 1;
}

[[gnu::target("sse4.2")]]
static uint32_t crc32c_hw(uint32_t crc, const unsigned char *p, size_t len) {
    uint32_t c = ~crc;
    while (len >= 8) {
        uint64_t v;
        __builtin_memcpy(&v, p, sizeof v);
        c = (uint32_t)_mm_crc32_u64(c, v);
        p += 8;
        len -= 8;
    }
    while (len-- > 0) c = _mm_crc32_u8(c, *p++);
    return ~c;
}
#endif

uint32_t nst_crc32c(uint32_t crc, const void *data, size_t len) {
    const unsigned char *p = data;
#if defined(NST_CRC32C_X86)
    if (NST_LIKELY(have_sse42())) return crc32c_hw(crc, p, len);
#endif
    return crc32c_table(crc, p, len);
}

bool nst_crc32c_hardware(void) {
#if defined(NST_CRC32C_X86)
    return have_sse42();
#else
    return false;
#endif
}
