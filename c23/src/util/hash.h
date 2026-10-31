/* Хеш-функции индекса. */
#ifndef NESTOR_UTIL_HASH_H
#define NESTOR_UTIL_HASH_H

#include <stddef.h>
#include <stdint.h>

/* FNV-1a 64 бита: короткий код, приличное распределение на коротких ключах. */
uint64_t nst_hash_fnv1a(const void *data, size_t len);

/* Финализатор splitmix64: разгоняет младшие биты, чтобы маска
 * hash & (cap - 1) не давала кластеров. */
static inline uint64_t nst_hash_mix64(uint64_t x) {
    x += 0x9E3779B97F4A7C15u;
    x = (x ^ (x >> 30)) * 0xBF58476D1CE4E5B9u;
    x = (x ^ (x >> 27)) * 0x94D049BB133111EBu;
    return x ^ (x >> 31);
}

/* Основной хеш ключа хранилища. */
static inline uint64_t nst_hash_key(const void *data, size_t len) {
    return nst_hash_mix64(nst_hash_fnv1a(data, len));
}

#endif /* NESTOR_UTIL_HASH_H */
