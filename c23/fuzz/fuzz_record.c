/* Фаззинг декодера записи: на входе — байты с диска, которым нельзя верить.
 *   ./scripts/fuzz.sh record 60
 */
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "store/record.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    nst_record rec;
    size_t consumed = 0;
    if (nst_record_decode(data, size, &rec, &consumed) != NST_OK) return 0;

    if (consumed > size) __builtin_trap();
    /* Успешный разбор обязан давать слайсы внутри входного буфера. */
    if (rec.key.ptr < data || rec.key.ptr + rec.key.len > data + size) __builtin_trap();
    if (rec.value.ptr < data || rec.value.ptr + rec.value.len > data + size) __builtin_trap();

    /* Round-trip: перекодирование обязано дать те же байты. Это ловит
     * расхождение кодировщика и декодера, которое санитайзеры не видят. */
    static uint8_t buf[NST_REC_HDR_SIZE + NST_MAX_KEY_BYTES + (16u << 20)];
    if (consumed > sizeof buf) return 0;
    size_t written = 0;
    if (nst_record_encode(&rec, buf, sizeof buf, &written) != NST_OK) return 0;
    if (written != consumed) __builtin_trap();
    if (memcmp(buf, data, written) != 0) __builtin_trap();
    return 0;
}
