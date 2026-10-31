#include "test.h"

#include <stdio.h>
#include <sys/stat.h>

#include "store/hint.h"
#include "store/segment.h"

typedef struct { int count; uint64_t last_off; nst_slice expect_first; bool first_ok; } hint_ctx;

static bool on_entry(nst_slice key, uint64_t offset, uint32_t rec_len, uint64_t seq,
                     uint8_t flags, void *user) {
    (void)rec_len; (void)seq; (void)flags;
    hint_ctx *c = user;
    if (c->count == 0) c->first_ok = nst_slice_eq(key, c->expect_first);
    c->count++;
    c->last_off = offset;
    return true;
}

NST_TEST(hint_roundtrip) {
    char dir[64];
    nst_test_tmpdir(dir);
    NST_CHECK_EQ(mkdir(dir, 0755), 0);

    nst_hint_writer w;
    NST_CHECK_STATUS(nst_hint_writer_init(&w, 7), NST_OK);
    NST_CHECK_STATUS(nst_hint_writer_add(&w, NST_SLICE_LIT("alpha"), 32, 40, 1, 0), NST_OK);
    NST_CHECK_STATUS(nst_hint_writer_add(&w, NST_SLICE_LIT("beta"), 72, 44, 2, 0), NST_OK);
    NST_CHECK_STATUS(nst_hint_writer_commit(&w, dir), NST_OK);
    nst_hint_writer_free(&w);

    hint_ctx ctx = { .expect_first = NST_SLICE_LIT("alpha") };
    NST_CHECK_STATUS(nst_hint_load(dir, 7, on_entry, &ctx), NST_OK);
    NST_CHECK_EQ(ctx.count, 2);
    NST_CHECK(ctx.first_ok);
    NST_CHECK_EQ(ctx.last_off, 72);

    NST_CHECK_STATUS(nst_hint_load(dir, 8, on_entry, &ctx), NST_E_NOTFOUND);

    nst_hint_remove(dir, 7);
    NST_CHECK_STATUS(nst_hint_load(dir, 7, on_entry, &ctx), NST_E_NOTFOUND);
    nst_test_rmdir_recursive(dir);
}

typedef struct { int count; uint64_t bytes; } scan_ctx;

static bool on_record(const nst_record *rec, uint64_t offset, uint32_t rec_len, void *user) {
    (void)offset;
    scan_ctx *c = user;
    c->count++;
    c->bytes += rec_len;
    NST_CHECK(rec->key.len > 0);
    return true;
}

NST_TEST(segment_scan_finds_all_records) {
    char dir[64];
    nst_test_tmpdir(dir);
    NST_CHECK_EQ(mkdir(dir, 0755), 0);

    nst_segment seg = {};
    NST_CHECK_STATUS(nst_segment_create(dir, 1, &seg), NST_OK);
    NST_CHECK_EQ(nst_segment_size(&seg), 32);

    uint8_t buf[256];
    for (int i = 0; i < 20; i++) {
        char key[16];
        int n = snprintf(key, sizeof key, "k%d", i);
        nst_record rec = { .key = nst_slice_bytes(key, (size_t)n),
                           .value = NST_SLICE_LIT("payload"), .seq = (uint64_t)i + 1 };
        size_t written = 0;
        NST_CHECK_STATUS(nst_record_encode(&rec, buf, sizeof buf, &written), NST_OK);
        NST_CHECK_STATUS(nst_segment_append(&seg, buf, written, nullptr), NST_OK);
    }
    uint64_t full_size = nst_segment_size(&seg);
    nst_segment_close(&seg);

    NST_CHECK_STATUS(nst_segment_open(dir, 1, false, &seg), NST_OK);
    scan_ctx ctx = {};
    uint64_t valid_end = 0;
    NST_CHECK_STATUS(nst_segment_scan(&seg, on_record, &ctx, &valid_end), NST_OK);
    NST_CHECK_EQ(ctx.count, 20);
    NST_CHECK_EQ(valid_end, full_size);
    NST_CHECK_EQ(ctx.bytes + 32, full_size);
    nst_segment_close(&seg);
    nst_test_rmdir_recursive(dir);
}

NST_TEST(segment_scan_stops_at_damaged_tail) {
    char dir[64];
    nst_test_tmpdir(dir);
    NST_CHECK_EQ(mkdir(dir, 0755), 0);

    nst_segment seg = {};
    NST_CHECK_STATUS(nst_segment_create(dir, 1, &seg), NST_OK);

    uint8_t buf[256];
    for (int i = 0; i < 5; i++) {
        nst_record rec = { .key = NST_SLICE_LIT("key"), .value = NST_SLICE_LIT("value"),
                           .seq = (uint64_t)i + 1 };
        size_t written = 0;
        NST_CHECK_STATUS(nst_record_encode(&rec, buf, sizeof buf, &written), NST_OK);
        NST_CHECK_STATUS(nst_segment_append(&seg, buf, written, nullptr), NST_OK);
    }
    uint64_t good_end = nst_segment_size(&seg);

    /* Половина шестой записи — как после отключения питания. */
    nst_record rec = { .key = NST_SLICE_LIT("key"), .value = NST_SLICE_LIT("value"), .seq = 6 };
    size_t written = 0;
    NST_CHECK_STATUS(nst_record_encode(&rec, buf, sizeof buf, &written), NST_OK);
    NST_CHECK_STATUS(nst_segment_append(&seg, buf, written / 2, nullptr), NST_OK);

    scan_ctx ctx = {};
    uint64_t valid_end = 0;
    NST_CHECK_STATUS(nst_segment_scan(&seg, on_record, &ctx, &valid_end), NST_OK);
    NST_CHECK_EQ(ctx.count, 5);
    NST_CHECK_EQ(valid_end, good_end);

    NST_CHECK_STATUS(nst_segment_truncate(&seg, valid_end), NST_OK);
    NST_CHECK_EQ(nst_segment_size(&seg), good_end);
    nst_segment_close(&seg);
    nst_test_rmdir_recursive(dir);
}

NST_TEST(segment_rejects_alien_file) {
    char dir[64];
    nst_test_tmpdir(dir);
    NST_CHECK_EQ(mkdir(dir, 0755), 0);

    char path[128];
    snprintf(path, sizeof path, "%s/000009.data", dir);
    FILE *f = fopen(path, "wb");
    NST_CHECK(f != nullptr);
    uint8_t junk[64] = {};
    memcpy(junk, "NOTNESTOR", 9);
    fwrite(junk, 1, sizeof junk, f);
    fclose(f);

    nst_segment seg = {};
    NST_CHECK_STATUS(nst_segment_open(dir, 9, false, &seg), NST_E_CORRUPT);
    nst_test_rmdir_recursive(dir);
}
