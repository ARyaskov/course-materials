/* CRC32C (полином Кастаньоли). Каждая запись и каждый заголовок в файлах
 * nestor защищены этой суммой: она ловит битые хвосты после падения
 * и повреждения на диске. */
#ifndef NESTOR_UTIL_CRC32C_H
#define NESTOR_UTIL_CRC32C_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Инкрементальный интерфейс: nst_crc32c(0, ...) для первого куска. */
uint32_t nst_crc32c(uint32_t crc, const void *data, size_t len);

/* Использует ли сборка аппаратную инструкцию (для STATS и тестов). */
bool nst_crc32c_hardware(void);

#endif /* NESTOR_UTIL_CRC32C_H */
