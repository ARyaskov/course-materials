#include "test.h"

#include <string.h>

#include "store/record.h"
#include "util/crc32c.h"
#include "util/endian.h"

NST_TEST(record_roundtrip) {
    uint8_t buf[512];
    nst_record in = {
        .key = NST_SLICE_LIT("user:42"),
        .value = NST_SLICE_LIT("{\"name\":\"ada\"}"),
        .seq = 7, .timestamp_ms = 1'700'000'000'000u, .flags = NST_REC_NONE,
    };

    size_t written = 0;
    NST_CHECK_STATUS(nst_record_encode(&in, buf, sizeof buf, &written), NST_OK);
    NST_CHECK_EQ(written, NST_REC_HDR_SIZE + in.key.len + in.value.len);

    nst_record out;
    size_t consumed = 0;
    NST_CHECK_STATUS(nst_record_decode(buf, written, &out, &consumed), NST_OK);
    NST_CHECK_EQ(consumed, written);
    NST_CHECK(nst_slice_eq(out.key, in.key));
    NST_CHECK(nst_slice_eq(out.value, in.value));
    NST_CHECK_EQ(out.seq, 7);
    NST_CHECK_EQ(out.timestamp_ms, 1'700'000'000'000u);
    NST_CHECK(!nst_record_is_tombstone(&out));
}

NST_TEST(record_tombstone_has_no_value) {
    uint8_t buf[128];
    nst_record in = { .key = NST_SLICE_LIT("k"), .seq = 1, .flags = NST_REC_TOMBSTONE };
    size_t written = 0;
    NST_CHECK_STATUS(nst_record_encode(&in, buf, sizeof buf, &written), NST_OK);

    nst_record out;
    NST_CHECK_STATUS(nst_record_decode(buf, written, &out, nullptr), NST_OK);
    NST_CHECK(nst_record_is_tombstone(&out));
    NST_CHECK_EQ(out.value.len, 0);
}

NST_TEST(record_rejects_empty_key) {
    uint8_t buf[64];
    nst_record in = { .key = {}, .value = NST_SLICE_LIT("v") };
    size_t written = 0;
    NST_CHECK_STATUS(nst_record_encode(&in, buf, sizeof buf, &written), NST_E_INVAL);
}

NST_TEST(record_rejects_small_buffer) {
    uint8_t buf[8];
    nst_record in = { .key = NST_SLICE_LIT("key"), .value = NST_SLICE_LIT("value") };
    size_t written = 0;
    NST_CHECK_STATUS(nst_record_encode(&in, buf, sizeof buf, &written), NST_E_TOOBIG);
}

NST_TEST(record_detects_bit_flip) {
    uint8_t buf[256];
    nst_record in = { .key = NST_SLICE_LIT("key"), .value = NST_SLICE_LIT("value"), .seq = 3 };
    size_t written = 0;
    NST_CHECK_STATUS(nst_record_encode(&in, buf, sizeof buf, &written), NST_OK);

    /* Один перевёрнутый бит в значении должен поймать CRC. */
    buf[written - 1] ^= 0x01u;
    nst_record out;
    NST_CHECK_STATUS(nst_record_decode(buf, written, &out, nullptr), NST_E_CORRUPT);
}

NST_TEST(record_detects_absurd_lengths) {
    uint8_t buf[256] = {};
    nst_store_le16(buf + 6, 10);
    nst_store_le32(buf + 8, 0xFFFF'FFFFu);      /* значение больше предела формата */
    NST_CHECK_STATUS(nst_record_peek_header(buf, nullptr, nullptr, nullptr, nullptr),
                     NST_E_CORRUPT);
}

NST_TEST(record_truncated_input) {
    uint8_t buf[256];
    nst_record in = { .key = NST_SLICE_LIT("key"), .value = NST_SLICE_LIT("longer value") };
    size_t written = 0;
    NST_CHECK_STATUS(nst_record_encode(&in, buf, sizeof buf, &written), NST_OK);

    nst_record out;
    NST_CHECK_STATUS(nst_record_decode(buf, written - 3, &out, nullptr), NST_E_CORRUPT);
    NST_CHECK_STATUS(nst_record_decode(buf, 4, &out, nullptr), NST_E_CORRUPT);
}

NST_TEST(record_size_overflow_is_detected) {
    size_t total = 0;
    NST_CHECK(!nst_record_size(SIZE_MAX, 1, &total));
    NST_CHECK(nst_record_size(10, 20, &total));
    NST_CHECK_EQ(total, NST_REC_HDR_SIZE + 30);
}

NST_TEST(crc32c_known_vectors) {
    /* Контрольные значения из RFC 3720 (iSCSI), приложение B. */
    uint8_t zeros[32] = {};
    NST_CHECK_EQ(nst_crc32c(0, zeros, sizeof zeros), 0x8A9136AAu);

    uint8_t ones[32];
    memset(ones, 0xFF, sizeof ones);
    NST_CHECK_EQ(nst_crc32c(0, ones, sizeof ones), 0x62A8AB43u);

    uint8_t inc[32];
    for (unsigned i = 0; i < 32; i++) inc[i] = (uint8_t)i;
    NST_CHECK_EQ(nst_crc32c(0, inc, sizeof inc), 0x46DD794Eu);
}

NST_TEST(crc32c_incremental_equals_whole) {
    const char data[] = "nestor log-structured storage";
    uint32_t whole = nst_crc32c(0, data, sizeof data - 1);
    uint32_t part = nst_crc32c(0, data, 7);
    part = nst_crc32c(part, data + 7, sizeof data - 1 - 7);
    NST_CHECK_EQ(whole, part);
}

NST_TEST(endian_roundtrip) {
    uint8_t buf[8];
    nst_store_le32(buf, 0x0123'4567u);
    NST_CHECK_EQ(buf[0], 0x67);
    NST_CHECK_EQ(buf[3], 0x01);
    NST_CHECK_EQ(nst_load_le32(buf), 0x0123'4567u);

    nst_store_le64(buf, 0xDEAD'BEEF'CAFE'BABEull);
    NST_CHECK_EQ(nst_load_le64(buf), 0xDEAD'BEEF'CAFE'BABEull);
}
