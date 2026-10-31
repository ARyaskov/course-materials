#include "test.h"

#include <stdalign.h>

#include "util/arena.h"
#include "util/pool.h"

NST_TEST(arena_alignment) {
    nst_arena a;
    nst_arena_init(&a, 1024);
    for (size_t align = 1; align <= 64; align *= 2) {
        void *p = nst_arena_alloc(&a, 17, align);
        NST_CHECK(p != nullptr);
        NST_CHECK_EQ((uintptr_t)p % align, 0);
    }
    nst_arena_destroy(&a);
}

NST_TEST(arena_grows_past_block) {
    nst_arena a;
    nst_arena_init(&a, 128);
    for (int i = 0; i < 100; i++) {
        uint64_t *p = NST_ARENA_NEW(&a, uint64_t);
        NST_CHECK(p != nullptr);
        *p = (uint64_t)i;
    }
    NST_CHECK(a.bytes_total >= 800);
    nst_arena_destroy(&a);
}

NST_TEST(arena_large_alloc_gets_own_block) {
    nst_arena a;
    nst_arena_init(&a, 64);
    void *p = nst_arena_alloc(&a, 100000, 16);
    NST_CHECK(p != nullptr);
    nst_arena_destroy(&a);
}

NST_TEST(arena_mark_restore) {
    nst_arena a;
    nst_arena_init(&a, 4096);
    (void)nst_arena_alloc(&a, 32, 8);
    nst_arena_mark mark = nst_arena_mark_get(&a);
    for (int i = 0; i < 50; i++) (void)nst_arena_alloc(&a, 200, 8);
    nst_arena_restore(&a, mark);
    void *p = nst_arena_alloc(&a, 8, 8);
    NST_CHECK(p != nullptr);
    nst_arena_destroy(&a);
}

NST_TEST(arena_memdup) {
    nst_arena a;
    nst_arena_init(&a, 256);
    const char src[] = "nestor";
    char *copy = nst_arena_memdup(&a, src, sizeof src);
    NST_CHECK(copy != nullptr);
    NST_CHECK_MEM(copy, src, sizeof src);
    nst_arena_destroy(&a);
}

NST_TEST(pool_reuses_slots) {
    nst_pool p;
    nst_pool_init(&p, 48, alignof(max_align_t), 8);

    void *a = nst_pool_acquire(&p);
    void *b = nst_pool_acquire(&p);
    NST_CHECK(a != nullptr && b != nullptr && a != b);
    NST_CHECK_EQ(p.live, 2);

    nst_pool_release(&p, a);
    void *c = nst_pool_acquire(&p);
    NST_CHECK_EQ(c == a, 1);       /* слот вернулся из свободного списка */
    NST_CHECK_EQ(p.live, 2);

    nst_pool_release(&p, b);
    nst_pool_release(&p, c);
    NST_CHECK_EQ(p.live, 0);
    nst_pool_destroy(&p);
}

NST_TEST(pool_grows_beyond_chunk) {
    nst_pool p;
    nst_pool_init(&p, 16, 8, 4);
    void *ptrs[40];
    for (int i = 0; i < 40; i++) {
        ptrs[i] = nst_pool_acquire(&p);
        NST_CHECK(ptrs[i] != nullptr);
    }
    NST_CHECK(p.capacity >= 40);
    for (int i = 0; i < 40; i++) nst_pool_release(&p, ptrs[i]);
    nst_pool_destroy(&p);
}
