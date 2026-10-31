#include "util/arena.h"

#include <stdckdint.h>
#include <stdlib.h>
#include <string.h>

#include "util/compiler.h"

struct nst_arena_block {
    nst_arena_block *prev;
    size_t cap;
    size_t used;
    alignas(alignof(max_align_t)) unsigned char data[];
};

/* Выравниваем абсолютный адрес, а не смещение в блоке: сам блок
 * выровнен только по alignof(max_align_t), а запросить могут больше
 * (например, 64 байта под строку кэша). */
static uintptr_t align_up_addr(uintptr_t v, size_t align) {
    return (v + (uintptr_t)align - 1) & ~((uintptr_t)align - 1);
}

void nst_arena_init(nst_arena *a, size_t block_size) {
    *a = (nst_arena){ .block_size = block_size ? block_size : NST_ARENA_DEFAULT_BLOCK };
}

void nst_arena_destroy(nst_arena *a) {
    nst_arena_block *b = a->head;
    while (b != nullptr) {
        nst_arena_block *prev = b->prev;
        free(b);
        b = prev;
    }
    *a = (nst_arena){ .block_size = a->block_size };
}

static nst_arena_block *arena_new_block(nst_arena *a, size_t need) {
    size_t cap = a->block_size;
    if (cap < need) cap = need;
    size_t total;
    if (ckd_add(&total, sizeof(nst_arena_block), cap)) return nullptr;
    nst_arena_block *b = malloc(total);
    if (b == nullptr) return nullptr;
    b->prev = a->head;
    b->cap = cap;
    b->used = 0;
    a->head = b;
    a->bytes_total += cap;
    return b;
}

void *nst_arena_alloc(nst_arena *a, size_t size, size_t align) {
    if (align == 0 || (align & (align - 1)) != 0) return nullptr;
    if (size == 0) size = 1;

    nst_arena_block *b = a->head;
    if (b != nullptr) {
        uintptr_t base = (uintptr_t)b->data;
        size_t off = (size_t)(align_up_addr(base + b->used, align) - base);
        size_t end;
        if (!ckd_add(&end, off, size) && end <= b->cap) {
            b->used = end;
            a->used_total += size;
            return b->data + off;
        }
    }

    size_t need;
    if (ckd_add(&need, size, align)) return nullptr;
    b = arena_new_block(a, need);
    if (b == nullptr) return nullptr;

    uintptr_t base = (uintptr_t)b->data;
    size_t off = (size_t)(align_up_addr(base + b->used, align) - base);
    b->used = off + size;
    a->used_total += size;
    return b->data + off;
}

void *nst_arena_memdup(nst_arena *a, const void *src, size_t n) {
    void *dst = nst_arena_alloc(a, n, 1);
    if (dst == nullptr) return nullptr;
    if (n > 0) memcpy(dst, src, n);
    return dst;
}

nst_arena_mark nst_arena_mark_get(const nst_arena *a) {
    return (nst_arena_mark){ .block = a->head, .used = a->head ? a->head->used : 0 };
}

void nst_arena_restore(nst_arena *a, nst_arena_mark mark) {
    while (a->head != nullptr && a->head != mark.block) {
        nst_arena_block *prev = a->head->prev;
        a->bytes_total -= a->head->cap;
        free(a->head);
        a->head = prev;
    }
    if (a->head != nullptr) a->head->used = mark.used;
}

void nst_arena_reset(nst_arena *a) {
    while (a->head != nullptr && a->head->prev != nullptr) {
        nst_arena_block *prev = a->head->prev;
        a->bytes_total -= a->head->cap;
        free(a->head);
        a->head = prev;
    }
    if (a->head != nullptr) a->head->used = 0;
    a->used_total = 0;
}
