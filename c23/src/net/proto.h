/* Текстовый протокол nestor с явными длинами: ключи и значения —
 * произвольные байты, поэтому длина указывается в заголовочной строке,
 * а тело передаётся как есть. Подробности — docs/protocol.md.
 *
 *   PUT <key_len> <value_len>\r\n<key><value>\r\n
 *   GET <key_len>\r\n<key>\r\n
 *   DEL <key_len>\r\n<key>\r\n
 *   PING\r\n   STATS\r\n   QUIT\r\n
 */
#ifndef NESTOR_NET_PROTO_H
#define NESTOR_NET_PROTO_H

#include <stdint.h>

#include <nestor/status.h>
#include "util/buf.h"
#include "util/slice.h"

typedef enum nst_cmd_kind : uint8_t {
    NST_CMD_NONE = 0,
    NST_CMD_PING,
    NST_CMD_GET,
    NST_CMD_PUT,
    NST_CMD_DEL,
    NST_CMD_STATS,
    NST_CMD_QUIT,
} nst_cmd_kind;

typedef struct nst_command {
    nst_cmd_kind kind;
    nst_slice key;    /* указывает внутрь входного буфера */
    nst_slice value;
} nst_command;

typedef struct nst_proto_limits {
    uint32_t max_key_bytes;
    uint32_t max_value_bytes;
} nst_proto_limits;

/* Разобрать одну команду из непрочитанной части in.
 *   NST_OK      — команда готова, *consumed байт можно потребить;
 *   NST_E_AGAIN — данных не хватает, ждём следующего чтения;
 *   NST_E_PROTO — протокольная ошибка, соединение закрывается;
 *   NST_E_TOOBIG — длины выходят за лимиты. */
[[nodiscard]] nst_status nst_proto_parse(const nst_buf *in, nst_proto_limits lim,
                                         nst_command *out, size_t *consumed);

/* Сериализация ответов в выходной буфер. */
[[nodiscard]] nst_status nst_proto_reply_ok(nst_buf *out);
[[nodiscard]] nst_status nst_proto_reply_pong(nst_buf *out);
[[nodiscard]] nst_status nst_proto_reply_value(nst_buf *out, nst_slice value);
[[nodiscard]] nst_status nst_proto_reply_nil(nst_buf *out);
[[nodiscard]] nst_status nst_proto_reply_error(nst_buf *out, const char *text);

const char *nst_cmd_name(nst_cmd_kind kind);

#endif /* NESTOR_NET_PROTO_H */
