#define _GNU_SOURCE
#include "test.h"

#include <fcntl.h>
#include <inttypes.h>
#include <pthread.h>
#include <stdio.h>
#include <unistd.h>

#include <nestor/nestor.h>

#include "store/format.h"
#include "util/io.h"
#include "util/slice.h"

static nst_options fast_opts(void) {
    nst_options o = nst_options_default();
    o.sync_mode = NST_SYNC_NEVER;
    o.background_compaction = false;
    o.max_segment_bytes = 64 * 1024;
    return o;
}

static void put_str(nst_db *db, const char *k, const char *v) {
    NST_CHECK_STATUS(nst_put(db, nst_slice_str(k), nst_slice_str(v)), NST_OK);
}

static void expect_value(nst_db *db, const char *k, const char *v) {
    nst_slice out;
    NST_CHECK_STATUS(nst_get(db, nst_slice_str(k), &out), NST_OK);
    NST_CHECK(nst_slice_eq(out, nst_slice_str(v)));
    nst_free_value(out);
}

NST_TEST(db_put_get_delete) {
    char dir[64];
    nst_test_tmpdir(dir);
    nst_options o = fast_opts();
    nst_db *db = nullptr;
    NST_CHECK_STATUS(nst_open(dir, &o, &db), NST_OK);

    put_str(db, "alpha", "1");
    put_str(db, "beta", "2");
    expect_value(db, "alpha", "1");
    expect_value(db, "beta", "2");

    put_str(db, "alpha", "updated");
    expect_value(db, "alpha", "updated");

    NST_CHECK(nst_contains(db, nst_slice_str("beta")));
    NST_CHECK_STATUS(nst_delete(db, nst_slice_str("beta")), NST_OK);
    NST_CHECK(!nst_contains(db, nst_slice_str("beta")));

    nst_slice out;
    NST_CHECK_STATUS(nst_get(db, nst_slice_str("beta"), &out), NST_E_NOTFOUND);
    NST_CHECK_STATUS(nst_delete(db, nst_slice_str("beta")), NST_E_NOTFOUND);

    nst_close(db);
    nst_test_rmdir_recursive(dir);
}

NST_TEST(db_binary_keys_and_values) {
    char dir[64];
    nst_test_tmpdir(dir);
    nst_options o = fast_opts();
    nst_db *db = nullptr;
    NST_CHECK_STATUS(nst_open(dir, &o, &db), NST_OK);

    const uint8_t key[] = { 0x00, 0xFF, 0x0A, 0x00 };
    const uint8_t val[] = { 0x01, 0x00, 0x02, 0x00, 0x03 };
    NST_CHECK_STATUS(nst_put(db, nst_slice_bytes(key, sizeof key),
                             nst_slice_bytes(val, sizeof val)), NST_OK);

    nst_slice out;
    NST_CHECK_STATUS(nst_get(db, nst_slice_bytes(key, sizeof key), &out), NST_OK);
    NST_CHECK_EQ(out.len, sizeof val);
    NST_CHECK_MEM(out.ptr, val, sizeof val);
    nst_free_value(out);

    /* Пустое значение — законное значение, а не отсутствие ключа. */
    NST_CHECK_STATUS(nst_put(db, nst_slice_str("empty"), (nst_slice){}), NST_OK);
    NST_CHECK_STATUS(nst_get(db, nst_slice_str("empty"), &out), NST_OK);
    NST_CHECK_EQ(out.len, 0);
    nst_free_value(out);

    nst_close(db);
    nst_test_rmdir_recursive(dir);
}

NST_TEST(db_rejects_bad_arguments) {
    char dir[64];
    nst_test_tmpdir(dir);
    nst_options o = fast_opts();
    o.max_value_bytes = 1024;
    nst_db *db = nullptr;
    NST_CHECK_STATUS(nst_open(dir, &o, &db), NST_OK);

    NST_CHECK_STATUS(nst_put(db, (nst_slice){}, nst_slice_str("v")), NST_E_INVAL);

    uint8_t big[2048] = {};
    NST_CHECK_STATUS(nst_put(db, nst_slice_str("k"), nst_slice_bytes(big, sizeof big)),
                     NST_E_TOOBIG);

    nst_slice out;
    NST_CHECK_STATUS(nst_get(db, (nst_slice){}, &out), NST_E_INVAL);

    nst_close(db);
    nst_test_rmdir_recursive(dir);
}

NST_TEST(db_reopen_restores_state) {
    char dir[64];
    nst_test_tmpdir(dir);
    nst_options o = fast_opts();
    o.max_segment_bytes = 8 * 1024;   /* заставляем сделать несколько сегментов */

    nst_db *db = nullptr;
    NST_CHECK_STATUS(nst_open(dir, &o, &db), NST_OK);
    char key[32], value[64];
    for (int i = 0; i < 500; i++) {
        snprintf(key, sizeof key, "key:%d", i);
        snprintf(value, sizeof value, "value-%d", i);
        put_str(db, key, value);
    }
    for (int i = 0; i < 500; i += 3) {
        snprintf(key, sizeof key, "key:%d", i);
        NST_CHECK_STATUS(nst_delete(db, nst_slice_str(key)), NST_OK);
    }
    NST_CHECK_STATUS(nst_sync(db), NST_OK);
    nst_close(db);

    NST_CHECK_STATUS(nst_open(dir, &o, &db), NST_OK);
    int alive = 0;
    for (int i = 0; i < 500; i++) {
        snprintf(key, sizeof key, "key:%d", i);
        snprintf(value, sizeof value, "value-%d", i);
        if (i % 3 == 0) {
            NST_CHECK(!nst_contains(db, nst_slice_str(key)));
        } else {
            expect_value(db, key, value);
            alive++;
        }
    }
    nst_stats s;
    nst_get_stats(db, &s);
    NST_CHECK_EQ(s.keys, alive);
    NST_CHECK(s.segments > 1);   /* сегмент 64 КиБ, данных больше */

    nst_close(db);
    nst_test_rmdir_recursive(dir);
}

NST_TEST(db_recovers_from_torn_tail) {
    char dir[64];
    nst_test_tmpdir(dir);
    nst_options o = fast_opts();
    o.max_segment_bytes = 16u << 20;   /* один сегмент на весь тест */

    nst_db *db = nullptr;
    NST_CHECK_STATUS(nst_open(dir, &o, &db), NST_OK);
    char key[32];
    for (int i = 0; i < 100; i++) {
        snprintf(key, sizeof key, "key:%d", i);
        put_str(db, key, "value");
    }
    NST_CHECK_STATUS(nst_sync(db), NST_OK);
    nst_close(db);

    /* Имитируем падение в середине записи: дописываем мусор в активный
     * сегмент, как будто write успел лечь только частично. */
    char path[128];
    snprintf(path, sizeof path, "%s/000001.data", dir);
    int fd = open(path, O_WRONLY | O_APPEND);
    NST_CHECK(fd >= 0);
    uint8_t garbage[37];
    for (size_t i = 0; i < sizeof garbage; i++) garbage[i] = (uint8_t)(0xA0 + i);
    NST_CHECK_STATUS(nst_write_full(fd, garbage, sizeof garbage), NST_OK);
    close(fd);

    NST_CHECK_STATUS(nst_open(dir, &o, &db), NST_OK);
    for (int i = 0; i < 100; i++) {
        snprintf(key, sizeof key, "key:%d", i);
        expect_value(db, key, "value");
    }
    /* Битый хвост усечён, запись продолжается с корректного места. */
    put_str(db, "after-crash", "ok");
    expect_value(db, "after-crash", "ok");
    nst_close(db);

    NST_CHECK_STATUS(nst_open(dir, &o, &db), NST_OK);
    expect_value(db, "after-crash", "ok");
    nst_close(db);
    nst_test_rmdir_recursive(dir);
}

NST_TEST(db_lock_prevents_second_writer) {
    char dir[64];
    nst_test_tmpdir(dir);
    nst_options o = fast_opts();

    nst_db *first = nullptr, *second = nullptr;
    NST_CHECK_STATUS(nst_open(dir, &o, &first), NST_OK);
    NST_CHECK_STATUS(nst_open(dir, &o, &second), NST_E_LOCKED);
    nst_close(first);

    NST_CHECK_STATUS(nst_open(dir, &o, &second), NST_OK);
    nst_close(second);
    nst_test_rmdir_recursive(dir);
}

NST_TEST(db_compaction_reclaims_space) {
    char dir[64];
    nst_test_tmpdir(dir);
    nst_options o = fast_opts();
    o.max_segment_bytes = 32 * 1024;

    nst_db *db = nullptr;
    NST_CHECK_STATUS(nst_open(dir, &o, &db), NST_OK);

    /* Перезаписываем 50 ключей много раз: почти всё на диске — мусор. */
    char key[32], value[128];
    memset(value, 'x', sizeof value - 1);
    value[sizeof value - 1] = 0;
    for (int round = 0; round < 200; round++) {
        for (int i = 0; i < 50; i++) {
            snprintf(key, sizeof key, "key:%d", i);
            put_str(db, key, value);
        }
    }

    nst_stats before;
    nst_get_stats(db, &before);
    NST_CHECK(before.total_bytes > before.live_bytes * 4);

    NST_CHECK_STATUS(nst_compact(db), NST_OK);

    nst_stats after;
    nst_get_stats(db, &after);
    NST_CHECK_EQ(after.keys, 50);
    NST_CHECK(after.total_bytes < before.total_bytes);
    NST_CHECK_EQ(after.compactions, 1);

    for (int i = 0; i < 50; i++) {
        snprintf(key, sizeof key, "key:%d", i);
        expect_value(db, key, value);
    }
    nst_close(db);

    /* После перезапуска данные читаются из слитого сегмента. */
    NST_CHECK_STATUS(nst_open(dir, &o, &db), NST_OK);
    nst_stats reopened;
    nst_get_stats(db, &reopened);
    NST_CHECK_EQ(reopened.keys, 50);
    for (int i = 0; i < 50; i++) {
        snprintf(key, sizeof key, "key:%d", i);
        expect_value(db, key, value);
    }
    nst_close(db);
    nst_test_rmdir_recursive(dir);
}

NST_TEST(db_compaction_does_not_resurrect_deleted) {
    char dir[64];
    nst_test_tmpdir(dir);
    nst_options o = fast_opts();
    o.max_segment_bytes = 8 * 1024;

    nst_db *db = nullptr;
    NST_CHECK_STATUS(nst_open(dir, &o, &db), NST_OK);
    char key[32];
    for (int i = 0; i < 200; i++) {
        snprintf(key, sizeof key, "key:%d", i);
        put_str(db, key, "0123456789012345678901234567890123456789");
    }
    for (int i = 0; i < 200; i += 2) {
        snprintf(key, sizeof key, "key:%d", i);
        NST_CHECK_STATUS(nst_delete(db, nst_slice_str(key)), NST_OK);
    }
    NST_CHECK_STATUS(nst_compact(db), NST_OK);
    nst_close(db);

    NST_CHECK_STATUS(nst_open(dir, &o, &db), NST_OK);
    for (int i = 0; i < 200; i++) {
        snprintf(key, sizeof key, "key:%d", i);
        NST_CHECK_EQ(nst_contains(db, nst_slice_str(key)), i % 2 == 1);
    }
    nst_close(db);
    nst_test_rmdir_recursive(dir);
}

static bool collect_keys(nst_slice key, void *user) {
    (void)key;
    (*(int *)user)++;
    return true;
}

NST_TEST(db_scan_visits_live_keys) {
    char dir[64];
    nst_test_tmpdir(dir);
    nst_options o = fast_opts();
    nst_db *db = nullptr;
    NST_CHECK_STATUS(nst_open(dir, &o, &db), NST_OK);

    char key[32];
    for (int i = 0; i < 30; i++) {
        snprintf(key, sizeof key, "key:%d", i);
        put_str(db, key, "v");
    }
    NST_CHECK_STATUS(nst_delete(db, nst_slice_str("key:5")), NST_OK);

    int seen = 0;
    NST_CHECK_STATUS(nst_scan(db, collect_keys, &seen), NST_OK);
    NST_CHECK_EQ(seen, 29);

    nst_close(db);
    nst_test_rmdir_recursive(dir);
}

typedef struct { nst_db *db; int id; int ops; int errors; } hammer_args;

static void *hammer(void *arg) {
    hammer_args *a = arg;
    char key[32], value[64];
    for (int i = 0; i < a->ops; i++) {
        snprintf(key, sizeof key, "t%d:k%d", a->id, i % 64);
        snprintf(value, sizeof value, "t%d-v%d", a->id, i);
        if (nst_put(a->db, nst_slice_str(key), nst_slice_str(value)) != NST_OK) a->errors++;

        nst_slice out;
        nst_status st = nst_get(a->db, nst_slice_str(key), &out);
        if (st == NST_OK) nst_free_value(out);
        else a->errors++;
    }
    return nullptr;
}

NST_TEST(db_concurrent_readers_and_writers) {
    char dir[64];
    nst_test_tmpdir(dir);
    nst_options o = fast_opts();
    o.background_compaction = true;
    o.compaction_interval_ms = 50;
    o.max_segment_bytes = 32 * 1024;

    nst_db *db = nullptr;
    NST_CHECK_STATUS(nst_open(dir, &o, &db), NST_OK);

    constexpr int THREADS = 4;
    pthread_t tids[THREADS];
    hammer_args args[THREADS] = {};
    for (int i = 0; i < THREADS; i++) {
        args[i] = (hammer_args){ .db = db, .id = i, .ops = 2000 };
        pthread_create(&tids[i], nullptr, hammer, &args[i]);
    }
    for (int i = 0; i < THREADS; i++) pthread_join(tids[i], nullptr);

    for (int i = 0; i < THREADS; i++) NST_CHECK_EQ(args[i].errors, 0);

    nst_stats s;
    nst_get_stats(db, &s);
    NST_CHECK_EQ(s.keys, THREADS * 64);
    nst_close(db);
    nst_test_rmdir_recursive(dir);
}

NST_TEST(db_read_only_mode) {
    char dir[64];
    nst_test_tmpdir(dir);
    nst_options o = fast_opts();
    nst_db *db = nullptr;
    NST_CHECK_STATUS(nst_open(dir, &o, &db), NST_OK);
    put_str(db, "k", "v");
    NST_CHECK_STATUS(nst_sync(db), NST_OK);
    nst_close(db);

    nst_options ro = o;
    ro.read_only = true;
    NST_CHECK_STATUS(nst_open(dir, &ro, &db), NST_OK);
    expect_value(db, "k", "v");
    NST_CHECK_STATUS(nst_put(db, nst_slice_str("k2"), nst_slice_str("v")), NST_E_INVAL);
    nst_close(db);
    nst_test_rmdir_recursive(dir);
}
