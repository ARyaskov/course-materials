#include "test.h"

#include "util/slice.h"

NST_TEST(slice_eq_and_cmp) {
    nst_slice a = NST_SLICE_LIT("nestor");
    nst_slice b = nst_slice_str("nestor");
    NST_CHECK(nst_slice_eq(a, b));
    NST_CHECK_EQ(a.len, 6);
    NST_CHECK(nst_slice_cmp(NST_SLICE_LIT("ab"), NST_SLICE_LIT("abc")) < 0);
    NST_CHECK(nst_slice_cmp(NST_SLICE_LIT("b"), NST_SLICE_LIT("a")) > 0);
    NST_CHECK_EQ(nst_slice_cmp(a, b), 0);
}

NST_TEST(slice_binary_safe) {
    const uint8_t raw[] = { 'a', 0, 'b' };
    nst_slice s = nst_slice_bytes(raw, sizeof raw);
    NST_CHECK_EQ(s.len, 3);
    NST_CHECK(!nst_slice_eq(s, NST_SLICE_LIT("a")));
    char buf[8];
    NST_CHECK(!nst_slice_to_cstr(s, buf, sizeof buf)); /* нулевой байт внутри */
}

NST_TEST(slice_sub_clamps) {
    nst_slice s = NST_SLICE_LIT("abcdef");
    NST_CHECK_EQ(nst_slice_sub(s, 2, 100).len, 4);
    NST_CHECK_EQ(nst_slice_sub(s, 100, 1).len, 0);
    NST_CHECK(nst_slice_eq(nst_slice_sub(s, 0, 3), NST_SLICE_LIT("abc")));
}

NST_TEST(slice_split_and_find) {
    nst_slice s = NST_SLICE_LIT("GET 12");
    nst_slice head, tail;
    NST_CHECK(nst_slice_split_byte(s, ' ', &head, &tail));
    NST_CHECK(nst_slice_eq(head, NST_SLICE_LIT("GET")));
    NST_CHECK(nst_slice_eq(tail, NST_SLICE_LIT("12")));
    NST_CHECK_EQ(nst_slice_find_byte(s, 'Z'), (long long)SIZE_MAX);
    NST_CHECK(!nst_slice_split_byte(NST_SLICE_LIT("nospace"), ' ', &head, &tail));
}

NST_TEST(slice_dup_roundtrip) {
    nst_slice src = NST_SLICE_LIT("value");
    nst_slice copy;
    NST_CHECK_STATUS(nst_slice_dup(src, &copy), NST_OK);
    NST_CHECK(nst_slice_eq(src, copy));
    NST_CHECK(copy.ptr != src.ptr);
    nst_free_value(copy);
}
