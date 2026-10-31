/* Арена: выделяем блоками, освобождаем всё разом.
 * Подходит для короткоживущих данных с одинаковым временем жизни —
 * разбор запроса, слияние сегментов при компакции. */
#ifndef NESTOR_UTIL_ARENA_H
#define NESTOR_UTIL_ARENA_H

#include <stdalign.h>
#include <stddef.h>
#include <stdint.h>

#include <nestor/status.h>

typedef struct nst_arena_block nst_arena_block;

typedef struct nst_arena {
    nst_arena_block *head;
    size_t block_size;   /* размер нового блока по умолчанию */
    size_t used_total;   /* сумма выданных байт (для метрик) */
    size_t bytes_total;  /* сумма ёмкостей блоков */
} nst_arena;

/* Позиция для отката: nst_arena_restore возвращает арену в это состояние. */
typedef struct nst_arena_mark {
    nst_arena_block *block;
    size_t used;
} nst_arena_mark;

constexpr size_t NST_ARENA_DEFAULT_BLOCK = 64u * 1024u;

void nst_arena_init(nst_arena *a, size_t block_size);
void nst_arena_destroy(nst_arena *a);

/* Выделение с выравниванием align (степень двойки). nullptr при нехватке
 * памяти или при переполнении размера. */
[[nodiscard]] void *nst_arena_alloc(nst_arena *a, size_t size, size_t align);

/* Выделение под объект типа T: NST_ARENA_NEW(a, struct foo) */
#define NST_ARENA_NEW(arena, T) ((T *)nst_arena_alloc((arena), sizeof(T), alignof(T)))
#define NST_ARENA_ARRAY(arena, T, n) \
    ((T *)nst_arena_alloc((arena), (n) * sizeof(T), alignof(T)))

/* Копия байтов в арене. */
[[nodiscard]] void *nst_arena_memdup(nst_arena *a, const void *src, size_t n);

nst_arena_mark nst_arena_mark_get(const nst_arena *a);
void nst_arena_restore(nst_arena *a, nst_arena_mark mark);

/* Освободить все блоки, кроме первого, и обнулить его. */
void nst_arena_reset(nst_arena *a);

#endif /* NESTOR_UTIL_ARENA_H */
