/* Фаззинг разбора протокола: libFuzzer подаёт произвольные байты,
 * парсер обязан вернуть один из статусов и не упасть.
 *   ./scripts/fuzz.sh proto 60
 */
#include <stddef.h>
#include <stdint.h>

#include "net/proto.h"
#include "util/buf.h"

/* Столько команд может поместиться в разумный вход; ограничение защищает
 * от бесконечного цикла, если парсер вернёт NST_OK с consumed == 0. */
constexpr int NST_FUZZ_MAX_COMMANDS = 4096;

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    nst_buf in;
    nst_buf_init(&in);
    if (nst_buf_append(&in, data, size) != NST_OK) { nst_buf_free(&in); return 0; }

    nst_proto_limits lim = { .max_key_bytes = 65535, .max_value_bytes = 1 << 20 };
    for (int i = 0; i < NST_FUZZ_MAX_COMMANDS; i++) {
        nst_command cmd;
        size_t consumed = 0;
        nst_status st = nst_proto_parse(&in, lim, &cmd, &consumed);
        if (st != NST_OK) break;

        /* Разбор обязан продвигаться: иначе цикл сервера зациклится. */
        if (consumed == 0) __builtin_trap();
        if (consumed > nst_buf_pending_len(&in)) __builtin_trap();

        /* Ключ и значение указывают внутрь буфера, копий парсер не делает. */
        nst_slice pending = nst_buf_pending(&in);
        if (cmd.key.len > 0 &&
            (cmd.key.ptr < pending.ptr ||
             cmd.key.ptr + cmd.key.len > pending.ptr + pending.len)) __builtin_trap();
        if (cmd.value.len > 0 &&
            (cmd.value.ptr < pending.ptr ||
             cmd.value.ptr + cmd.value.len > pending.ptr + pending.len)) __builtin_trap();

        nst_buf_consume(&in, consumed);
    }
    nst_buf_free(&in);
    return 0;
}
