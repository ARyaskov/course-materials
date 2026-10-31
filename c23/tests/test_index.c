#include "test.h"

#include <stdio.h>

#include "store/index.h"
#include "util/hash.h"

static nst_loc loc_of(uint64_t seq, uint64_t off) {
    return (nst_loc){ .offset = off, .seq = seq, .file_id = 1, .rec_len = 64 };
}

NST_TEST(index_put_get_remove) {
    nst_index ix;
    NST_CHECK_STATUS(nst_index_init(&ix, 16), NST_OK);

    nst_slice key = NST_SLICE_LIT("alpha");
    bool stored = false;
    NST_CHECK_STATUS(nst_index_put(&ix, key, loc_of(1, 100), &stored, nullptr), NST_OK);
    NST_CHECK(stored);
    NST_CHECK_EQ(nst_index_count(&ix), 1);

    nst_loc got;
    NST_CHECK(nst_index_get(&ix, key, &got));
    NST_CHECK_EQ(got.offset, 100);

    NST_CHECK(nst_index_remove(&ix, key, nullptr));
    NST_CHECK(!nst_index_get(&ix, key, nullptr));
    NST_CHECK_EQ(nst_index_count(&ix), 0);
    NST_CHECK(!nst_index_remove(&ix, key, nullptr));

    nst_index_destroy(&ix);
}

NST_TEST(index_keeps_newest_version) {
    nst_index ix;
    NST_CHECK_STATUS(nst_index_init(&ix, 16), NST_OK);
    nst_slice key = NST_SLICE_LIT("k");

    NST_CHECK_STATUS(nst_index_put(&ix, key, loc_of(5, 500), nullptr, nullptr), NST_OK);

    /* Более старая версия не должна затирать более новую: при восстановлении
     * порядок обхода сегментов не гарантирован. */
    bool stored = true;
    NST_CHECK_STATUS(nst_index_put(&ix, key, loc_of(2, 200), &stored, nullptr), NST_OK);
    NST_CHECK(!stored);

    nst_loc got;
    NST_CHECK(nst_index_get(&ix, key, &got));
    NST_CHECK_EQ(got.seq, 5);

    NST_CHECK_STATUS(nst_index_put(&ix, key, loc_of(9, 900), &stored, nullptr), NST_OK);
    NST_CHECK(stored);
    NST_CHECK(nst_index_get(&ix, key, &got));
    NST_CHECK_EQ(got.offset, 900);

    nst_index_destroy(&ix);
}

NST_TEST(index_grows_and_keeps_all_keys) {
    nst_index ix;
    NST_CHECK_STATUS(nst_index_init(&ix, 16), NST_OK);

    constexpr int N = 5000;
    char key[32];
    for (int i = 0; i < N; i++) {
        int n = snprintf(key, sizeof key, "key:%d", i);
        NST_CHECK_STATUS(nst_index_put(&ix, nst_slice_bytes(key, (size_t)n),
                                       loc_of((uint64_t)i + 1, (uint64_t)i * 64),
                                       nullptr, nullptr), NST_OK);
    }
    NST_CHECK_EQ(nst_index_count(&ix), N);

    for (int i = 0; i < N; i++) {
        int n = snprintf(key, sizeof key, "key:%d", i);
        nst_loc got;
        NST_CHECK(nst_index_get(&ix, nst_slice_bytes(key, (size_t)n), &got));
        NST_CHECK_EQ(got.offset, (uint64_t)i * 64);
    }
    nst_index_destroy(&ix);
}

NST_TEST(index_reuses_tombstone_slots) {
    nst_index ix;
    NST_CHECK_STATUS(nst_index_init(&ix, 64), NST_OK);
    char key[32];

    /* Много циклов вставки-удаления не должны бесконечно растить таблицу. */
    for (int round = 0; round < 50; round++) {
        for (int i = 0; i < 20; i++) {
            int n = snprintf(key, sizeof key, "k%d", i);
            NST_CHECK_STATUS(nst_index_put(&ix, nst_slice_bytes(key, (size_t)n),
                                           loc_of((uint64_t)(round * 20 + i + 1), 0),
                                           nullptr, nullptr), NST_OK);
        }
        for (int i = 0; i < 20; i++) {
            int n = snprintf(key, sizeof key, "k%d", i);
            NST_CHECK(nst_index_remove(&ix, nst_slice_bytes(key, (size_t)n), nullptr));
        }
    }
    NST_CHECK_EQ(nst_index_count(&ix), 0);
    nst_index_destroy(&ix);
}

static bool count_cb(nst_slice key, nst_loc loc, void *user) {
    (void)key; (void)loc;
    (*(int *)user)++;
    return true;
}

static bool stop_cb(nst_slice key, nst_loc loc, void *user) {
    (void)key; (void)loc;
    (*(int *)user)++;
    return false;
}

NST_TEST(index_foreach_visits_and_stops) {
    nst_index ix;
    NST_CHECK_STATUS(nst_index_init(&ix, 16), NST_OK);
    char key[16];
    for (int i = 0; i < 100; i++) {
        int n = snprintf(key, sizeof key, "k%d", i);
        NST_CHECK_STATUS(nst_index_put(&ix, nst_slice_bytes(key, (size_t)n),
                                       loc_of((uint64_t)i + 1, 0), nullptr, nullptr), NST_OK);
    }
    int seen = 0;
    nst_index_foreach(&ix, count_cb, &seen);
    NST_CHECK_EQ(seen, 100);

    seen = 0;
    nst_index_foreach(&ix, stop_cb, &seen);
    NST_CHECK_EQ(seen, 1);
    nst_index_destroy(&ix);
}

NST_TEST(hash_distribution_is_reasonable) {
    /* Ключи вида key:0..key:N не должны кучковаться в одном ведре. */
    constexpr size_t BUCKETS = 256;
    int hist[BUCKETS] = {};
    char key[32];
    for (int i = 0; i < 20000; i++) {
        int n = snprintf(key, sizeof key, "key:%d", i);
        hist[nst_hash_key(key, (size_t)n) & (BUCKETS - 1)]++;
    }
    int max = 0, min = 1 << 30;
    for (size_t i = 0; i < BUCKETS; i++) {
        if (hist[i] > max) max = hist[i];
        if (hist[i] < min) min = hist[i];
    }
    NST_CHECK(max < 160);   /* среднее 78 */
    NST_CHECK(min > 20);
}
