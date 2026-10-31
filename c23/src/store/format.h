/* Константы формата на диске. Подробное описание — docs/format.md.
 * Всё кодируется явно, little-endian; структуры на диск не пишутся. */
#ifndef NESTOR_STORE_FORMAT_H
#define NESTOR_STORE_FORMAT_H

#include <stddef.h>
#include <stdint.h>

constexpr uint32_t NST_FORMAT_VERSION = 1;

/* Потолок для путей: каталог базы ограничен 3072 байтами, имя файла — 32. */
constexpr size_t NST_PATH_MAX = 4096;

/* Заголовок файла сегмента данных: 32 байта. */
constexpr size_t NST_SEG_HDR_SIZE = 32;
constexpr uint8_t NST_SEG_MAGIC[8] = { 'N', 'S', 'T', 'S', 'E', 'G', 0x00, 0x01 };

/* Заголовок hint-файла: 32 байта, та же раскладка. */
constexpr uint8_t NST_HINT_MAGIC[8] = { 'N', 'S', 'T', 'H', 'N', 'T', 0x00, 0x01 };

/* Заголовок записи: 28 байт.
 *   0  u32 crc32c поля 4..конца записи (включая ключ и значение)
 *   4  u8  flags
 *   5  u8  reserved (0)
 *   6  u16 key_len
 *   8  u32 value_len
 *  12  u64 seq
 *  20  u64 timestamp_ms
 *  28  key[key_len]
 *      value[value_len]  (для tombstone value_len == 0)
 */
constexpr size_t NST_REC_HDR_SIZE = 28;

enum nst_rec_flags : uint8_t {
    NST_REC_NONE      = 0b0000'0000,
    NST_REC_TOMBSTONE = 0b0000'0001,
};

/* Запись hint-файла: 24 байта + ключ.
 *   0  u64 record_offset
 *   8  u32 record_len
 *  12  u64 seq
 *  20  u16 key_len
 *  22  u8  flags
 *  23  u8  reserved
 */
constexpr size_t NST_HINT_ENT_SIZE = 24;

constexpr uint32_t NST_MAX_KEY_BYTES   = 65535;        /* ограничение u16 в заголовке */
constexpr uint32_t NST_MAX_VALUE_BYTES = 64u << 20;    /* 64 МиБ, потолок формата */
constexpr uint64_t NST_MAX_SEGMENT_BYTES = 4ull << 30; /* 4 ГиБ на сегмент */

static_assert(NST_REC_HDR_SIZE == 28, "формат записи зафиксирован");
static_assert(NST_SEG_HDR_SIZE == 32, "формат заголовка сегмента зафиксирован");
static_assert(NST_HINT_ENT_SIZE == 24, "формат hint-записи зафиксирован");
static_assert(sizeof(NST_SEG_MAGIC) == 8);
static_assert(NST_MAX_KEY_BYTES <= UINT16_MAX, "key_len кодируется в u16");

#endif /* NESTOR_STORE_FORMAT_H */
