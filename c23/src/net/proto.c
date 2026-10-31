#include "net/proto.h"

#include <errno.h>
#include <stdlib.h>
#include <string.h>

#include "util/compiler.h"

constexpr size_t NST_PROTO_MAX_LINE = 64;

const char *nst_cmd_name(nst_cmd_kind kind) {
    switch (kind) {
        case NST_CMD_NONE:  return "NONE";
        case NST_CMD_PING:  return "PING";
        case NST_CMD_GET:   return "GET";
        case NST_CMD_PUT:   return "PUT";
        case NST_CMD_DEL:   return "DEL";
        case NST_CMD_STATS: return "STATS";
        case NST_CMD_QUIT:  return "QUIT";
    }
    return "?";
}

/* Разбор десятичного числа без знака из слайса: без strtoull, потому что
 * данные не заканчиваются нулём и приходят из сети. */
static bool parse_u32(nst_slice s, uint32_t *out) {
    if (s.len == 0 || s.len > 10) return false;
    uint64_t v = 0;
    for (size_t i = 0; i < s.len; i++) {
        uint8_t c = s.ptr[i];
        if (c < '0' || c > '9') return false;
        v = v * 10 + (uint64_t)(c - '0');
        if (v > UINT32_MAX) return false;
    }
    *out = (uint32_t)v;
    return true;
}

static nst_slice next_token(nst_slice *rest) {
    while (rest->len > 0 && rest->ptr[0] == ' ') *rest = nst_slice_sub(*rest, 1, rest->len);
    nst_slice head, tail;
    if (nst_slice_split_byte(*rest, ' ', &head, &tail)) {
        *rest = tail;
        return head;
    }
    nst_slice all = *rest;
    *rest = (nst_slice){ .ptr = rest->ptr + rest->len, .len = 0 };
    return all;
}

static bool token_eq_ci(nst_slice tok, const char *word) {
    size_t n = strlen(word);
    if (tok.len != n) return false;
    for (size_t i = 0; i < n; i++) {
        uint8_t c = tok.ptr[i];
        if (c >= 'a' && c <= 'z') c = (uint8_t)(c - 'a' + 'A');
        if (c != (uint8_t)word[i]) return false;
    }
    return true;
}

nst_status nst_proto_parse(const nst_buf *in, nst_proto_limits lim, nst_command *out,
                           size_t *consumed) {
    nst_slice pending = nst_buf_pending(in);
    if (pending.len == 0) return NST_E_AGAIN;

    size_t nl = nst_slice_find_byte(pending, '\n');
    if (nl == SIZE_MAX) {
        /* Строка ещё не пришла целиком — но и бесконечно её ждать нельзя. */
        return pending.len > NST_PROTO_MAX_LINE ? NST_E_PROTO : NST_E_AGAIN;
    }
    if (nl > NST_PROTO_MAX_LINE) return NST_E_PROTO;

    size_t line_len = nl;
    if (line_len > 0 && pending.ptr[line_len - 1] == '\r') line_len--;
    nst_slice line = nst_slice_sub(pending, 0, line_len);
    size_t header_len = nl + 1;

    nst_slice rest = line;
    nst_slice verb = next_token(&rest);
    if (verb.len == 0) return NST_E_PROTO;

    *out = (nst_command){};

    if (token_eq_ci(verb, "PING"))  { out->kind = NST_CMD_PING;  *consumed = header_len; return NST_OK; }
    if (token_eq_ci(verb, "STATS")) { out->kind = NST_CMD_STATS; *consumed = header_len; return NST_OK; }
    if (token_eq_ci(verb, "QUIT"))  { out->kind = NST_CMD_QUIT;  *consumed = header_len; return NST_OK; }

    bool is_put = token_eq_ci(verb, "PUT");
    bool is_get = token_eq_ci(verb, "GET");
    bool is_del = token_eq_ci(verb, "DEL");
    if (!is_put && !is_get && !is_del) return NST_E_PROTO;

    uint32_t key_len = 0, value_len = 0;
    if (!parse_u32(next_token(&rest), &key_len)) return NST_E_PROTO;
    if (is_put && !parse_u32(next_token(&rest), &value_len)) return NST_E_PROTO;
    if (next_token(&rest).len != 0) return NST_E_PROTO;   /* лишний аргумент */

    if (key_len == 0) return NST_E_PROTO;
    if (key_len > lim.max_key_bytes || value_len > lim.max_value_bytes) return NST_E_TOOBIG;

    /* Тело: ключ, значение и завершающий CRLF. */
    size_t body = (size_t)key_len + value_len + 2;
    if (pending.len - header_len < body) return NST_E_AGAIN;

    const uint8_t *body_ptr = pending.ptr + header_len;
    if (body_ptr[key_len + value_len] != '\r' || body_ptr[key_len + value_len + 1] != '\n')
        return NST_E_PROTO;

    out->kind = is_put ? NST_CMD_PUT : (is_get ? NST_CMD_GET : NST_CMD_DEL);
    out->key = (nst_slice){ .ptr = body_ptr, .len = key_len };
    out->value = (nst_slice){ .ptr = body_ptr + key_len, .len = value_len };
    *consumed = header_len + body;
    return NST_OK;
}

nst_status nst_proto_reply_ok(nst_buf *out) { return nst_buf_append(out, "+OK\r\n", 5); }
nst_status nst_proto_reply_pong(nst_buf *out) { return nst_buf_append(out, "+PONG\r\n", 7); }
nst_status nst_proto_reply_nil(nst_buf *out) { return nst_buf_append(out, "$-1\r\n", 5); }

nst_status nst_proto_reply_value(nst_buf *out, nst_slice value) {
    NST_TRY(nst_buf_printf(out, "$%zu\r\n", value.len));
    NST_TRY(nst_buf_append_slice(out, value));
    return nst_buf_append(out, "\r\n", 2);
}

nst_status nst_proto_reply_error(nst_buf *out, const char *text) {
    return nst_buf_printf(out, "-ERR %s\r\n", text);
}
