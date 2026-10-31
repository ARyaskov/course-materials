#include "util/pool.h"

#include <stdckdint.h>
#include <stdlib.h>
#include <string.h>

#include "util/compiler.h"

struct nst_pool_chunk {
    nst_pool_chunk *next;
    unsigned char data[];
};

static size_t align_up(size_t v, size_t a) { return (v + (a - 1)) & ~(a - 1); }
static uintptr_t align_up_addr(uintptr_t v, size_t a) {
    return (v + (uintptr_t)a - 1) & ~((uintptr_t)a - 1);
}

void nst_pool_init(nst_pool *p, size_t obj_size, size_t obj_align, size_t per_chunk) {
    if (obj_align < alignof(void *)) obj_align = alignof(void *);
    if (obj_size < sizeof(void *)) obj_size = sizeof(void *);
    *p = (nst_pool){
        .obj_size = align_up(obj_size, obj_align),
        .obj_align = obj_align,
        .per_chunk = per_chunk ? per_chunk : 64,
    };
}

void nst_pool_destroy(nst_pool *p) {
    nst_pool_chunk *c = p->chunks;
    while (c != nullptr) {
        nst_pool_chunk *next = c->next;
        free(c);
        c = next;
    }
    *p = (nst_pool){ .obj_size = p->obj_size, .obj_align = p->obj_align,
                     .per_chunk = p->per_chunk };
}

static bool pool_grow(nst_pool *p) {
    size_t payload;
    if (ckd_mul(&payload, p->obj_size, p->per_chunk)) return false;
    size_t total;
    if (ckd_add(&total, sizeof(nst_pool_chunk) + p->obj_align, payload)) return false;

    nst_pool_chunk *c = malloc(total);
    if (c == nullptr) return false;
    c->next = p->chunks;
    p->chunks = c;

    uintptr_t raw = (uintptr_t)c->data;
    unsigned char *base = (unsigned char *)align_up_addr(raw, p->obj_align);
    for (size_t i = 0; i < p->per_chunk; i++) {
        void *slot = base + i * p->obj_size;
        memcpy(slot, &p->free_list, sizeof(void *));
        p->free_list = slot;
    }
    p->capacity += p->per_chunk;
    return true;
}

void *nst_pool_acquire(nst_pool *p) {
    if (p->free_list == nullptr && !pool_grow(p)) return nullptr;
    void *slot = p->free_list;
    memcpy(&p->free_list, slot, sizeof(void *));
    p->live++;
#ifndef NDEBUG
    memset(slot, 0xCD, p->obj_size); /* заметный мусор вместо чужих данных */
#endif
    return slot;
}

void nst_pool_release(nst_pool *p, void *obj) {
    if (obj == nullptr) return;
#ifndef NDEBUG
    memset(obj, 0xDD, p->obj_size);
#endif
    memcpy(obj, &p->free_list, sizeof(void *));
    p->free_list = obj;
    p->live--;
}
