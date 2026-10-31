/* Пул объектов одного размера. Свободный список хранится внутри самих
 * блоков, поэтому накладных расходов на элемент нет. */
#ifndef NESTOR_UTIL_POOL_H
#define NESTOR_UTIL_POOL_H

#include <stddef.h>
#include <stdint.h>

typedef struct nst_pool_chunk nst_pool_chunk;

typedef struct nst_pool {
    nst_pool_chunk *chunks;
    void *free_list;
    size_t obj_size;      /* фактический размер слота (с выравниванием) */
    size_t obj_align;
    size_t per_chunk;
    size_t live;          /* сколько объектов выдано и не возвращено */
    size_t capacity;
} nst_pool;

void nst_pool_init(nst_pool *p, size_t obj_size, size_t obj_align, size_t per_chunk);
void nst_pool_destroy(nst_pool *p);

[[nodiscard]] void *nst_pool_acquire(nst_pool *p);
void nst_pool_release(nst_pool *p, void *obj);

#endif /* NESTOR_UTIL_POOL_H */
