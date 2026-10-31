#include "test.h"

#include "net/proto.h"

static const nst_proto_limits LIM = { .max_key_bytes = 65535, .max_value_bytes = 1 << 20 };

static void feed(nst_buf *b, const char *s) {
    NST_CHECK_STATUS(nst_buf_append(b, s, strlen(s)), NST_OK);
}

NST_TEST(proto_simple_commands) {
    nst_buf in;
    nst_buf_init(&in);
    feed(&in, "PING\r\nSTATS\r\nQUIT\r\n");

    nst_cmd_kind expected[] = { NST_CMD_PING, NST_CMD_STATS, NST_CMD_QUIT };
    for (size_t i = 0; i < 3; i++) {
        nst_command cmd;
        size_t used = 0;
        NST_CHECK_STATUS(nst_proto_parse(&in, LIM, &cmd, &used), NST_OK);
        NST_CHECK_EQ(cmd.kind, expected[i]);
        nst_buf_consume(&in, used);
    }
    nst_command cmd;
    size_t used = 0;
    NST_CHECK_STATUS(nst_proto_parse(&in, LIM, &cmd, &used), NST_E_AGAIN);
    nst_buf_free(&in);
}

NST_TEST(proto_put_get_del) {
    nst_buf in;
    nst_buf_init(&in);
    feed(&in, "PUT 3 5\r\nkeyvalue\r\nGET 3\r\nkey\r\nDEL 3\r\nkey\r\n");

    nst_command cmd;
    size_t used = 0;
    NST_CHECK_STATUS(nst_proto_parse(&in, LIM, &cmd, &used), NST_OK);
    NST_CHECK_EQ(cmd.kind, NST_CMD_PUT);
    NST_CHECK(nst_slice_eq(cmd.key, NST_SLICE_LIT("key")));
    NST_CHECK(nst_slice_eq(cmd.value, NST_SLICE_LIT("value")));
    nst_buf_consume(&in, used);

    NST_CHECK_STATUS(nst_proto_parse(&in, LIM, &cmd, &used), NST_OK);
    NST_CHECK_EQ(cmd.kind, NST_CMD_GET);
    NST_CHECK(nst_slice_eq(cmd.key, NST_SLICE_LIT("key")));
    nst_buf_consume(&in, used);

    NST_CHECK_STATUS(nst_proto_parse(&in, LIM, &cmd, &used), NST_OK);
    NST_CHECK_EQ(cmd.kind, NST_CMD_DEL);
    nst_buf_free(&in);
}

NST_TEST(proto_handles_byte_by_byte_input) {
    /* Сеть режет поток произвольно: парсер обязан переживать любой разрез. */
    const char *wire = "PUT 3 5\r\nkeyvalue\r\n";
    nst_buf in;
    nst_buf_init(&in);

    nst_command cmd;
    size_t used = 0;
    for (size_t i = 0; wire[i] != '\0'; i++) {
        NST_CHECK_STATUS(nst_buf_append(&in, &wire[i], 1), NST_OK);
        nst_status st = nst_proto_parse(&in, LIM, &cmd, &used);
        if (wire[i + 1] != '\0') NST_CHECK_STATUS(st, NST_E_AGAIN);
        else NST_CHECK_STATUS(st, NST_OK);
    }
    NST_CHECK(nst_slice_eq(cmd.value, NST_SLICE_LIT("value")));
    nst_buf_free(&in);
}

NST_TEST(proto_binary_payload_with_nulls) {
    nst_buf in;
    nst_buf_init(&in);
    NST_CHECK_STATUS(nst_buf_append(&in, "PUT 3 4\r\n", 9), NST_OK);
    const uint8_t body[] = { 'a', 0x00, 'b', 0x00, 0xFF, 0x00, 0x01, '\r', '\n' };
    NST_CHECK_STATUS(nst_buf_append(&in, body, sizeof body), NST_OK);

    nst_command cmd;
    size_t used = 0;
    NST_CHECK_STATUS(nst_proto_parse(&in, LIM, &cmd, &used), NST_OK);
    NST_CHECK_EQ(cmd.key.len, 3);
    NST_CHECK_EQ(cmd.value.len, 4);
    NST_CHECK_EQ(cmd.value.ptr[3], 0x01);
    nst_buf_free(&in);
}

NST_TEST(proto_rejects_garbage) {
    struct { const char *wire; nst_status expected; } cases[] = {
        { "NOPE\r\n",             NST_E_PROTO },
        { "GET\r\n",              NST_E_PROTO },
        { "GET abc\r\n",          NST_E_PROTO },
        { "GET 0\r\n",            NST_E_PROTO },
        { "GET 3 4\r\n",          NST_E_PROTO },
        { "PUT 3\r\n",            NST_E_PROTO },
        { "PUT 3 5\r\nkeyvaluX",  NST_E_AGAIN },
        { "GET 99999999\r\n",     NST_E_TOOBIG },
    };
    for (size_t i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        nst_buf in;
        nst_buf_init(&in);
        feed(&in, cases[i].wire);
        nst_command cmd;
        size_t used = 0;
        NST_CHECK_STATUS(nst_proto_parse(&in, LIM, &cmd, &used), cases[i].expected);
        nst_buf_free(&in);
    }
}

NST_TEST(proto_rejects_overlong_line) {
    nst_buf in;
    nst_buf_init(&in);
    char junk[256];
    memset(junk, 'A', sizeof junk);
    NST_CHECK_STATUS(nst_buf_append(&in, junk, sizeof junk), NST_OK);

    nst_command cmd;
    size_t used = 0;
    NST_CHECK_STATUS(nst_proto_parse(&in, LIM, &cmd, &used), NST_E_PROTO);
    nst_buf_free(&in);
}

NST_TEST(proto_case_insensitive_verbs) {
    nst_buf in;
    nst_buf_init(&in);
    feed(&in, "ping\r\n");
    nst_command cmd;
    size_t used = 0;
    NST_CHECK_STATUS(nst_proto_parse(&in, LIM, &cmd, &used), NST_OK);
    NST_CHECK_EQ(cmd.kind, NST_CMD_PING);
    nst_buf_free(&in);
}

NST_TEST(proto_replies) {
    nst_buf out;
    nst_buf_init(&out);
    NST_CHECK_STATUS(nst_proto_reply_ok(&out), NST_OK);
    NST_CHECK_STATUS(nst_proto_reply_nil(&out), NST_OK);
    NST_CHECK_STATUS(nst_proto_reply_value(&out, NST_SLICE_LIT("hi")), NST_OK);
    NST_CHECK_STATUS(nst_proto_reply_error(&out, "bad"), NST_OK);

    nst_slice all = nst_buf_pending(&out);
    NST_CHECK(nst_slice_starts_with(all, NST_SLICE_LIT("+OK\r\n$-1\r\n$2\r\nhi\r\n-ERR bad\r\n")));
    NST_CHECK_EQ(all.len, strlen("+OK\r\n$-1\r\n$2\r\nhi\r\n-ERR bad\r\n"));
    nst_buf_free(&out);
}

NST_TEST(buf_grows_and_consumes) {
    nst_buf b;
    nst_buf_init(&b);
    for (int i = 0; i < 1000; i++)
        NST_CHECK_STATUS(nst_buf_append(&b, "0123456789", 10), NST_OK);
    NST_CHECK_EQ(b.len, 10000);

    nst_buf_consume(&b, 9999);
    NST_CHECK_EQ(nst_buf_pending_len(&b), 1);
    nst_buf_compact(&b);
    NST_CHECK_EQ(b.read_pos, 0);
    NST_CHECK_EQ(b.len, 1);

    nst_buf_consume(&b, 100);   /* потребить больше, чем есть, — не падать */
    NST_CHECK_EQ(nst_buf_pending_len(&b), 0);
    nst_buf_free(&b);
}

NST_TEST(buf_printf_appends_without_nul) {
    nst_buf b;
    nst_buf_init(&b);
    NST_CHECK_STATUS(nst_buf_printf(&b, "%s=%d", "port", 7717), NST_OK);
    NST_CHECK_EQ(b.len, 9);
    NST_CHECK_MEM(b.data, "port=7717", 9);
    NST_CHECK_STATUS(nst_buf_printf(&b, ";%c", 'x'), NST_OK);
    NST_CHECK_MEM(b.data, "port=7717;x", 11);
    nst_buf_free(&b);
}
