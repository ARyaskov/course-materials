#include "util/hash.h"

uint64_t nst_hash_fnv1a(const void *data, size_t len) {
    constexpr uint64_t offset_basis = 0xCBF2'9CE4'8422'2325u;
    constexpr uint64_t prime        = 0x0000'0100'0000'01B3u;

    const unsigned char *p = data;
    uint64_t h = offset_basis;
    for (size_t i = 0; i < len; i++) {
        h ^= p[i];
        h *= prime;
    }
    return h;
}
