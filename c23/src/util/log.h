/* Логирование: уровень, позиция в коде, поток, монотонная метка.
 * Формат строки:
 *   2026-09-07T10:11:12.345Z INFO  [tid 4711] db.c:214 open: 12 segments
 */
#ifndef NESTOR_UTIL_LOG_H
#define NESTOR_UTIL_LOG_H

#include <stdint.h>
#include <stdio.h>

#include "util/compiler.h"

typedef enum nst_log_level : uint8_t {
    NST_LOG_TRACE = 0,
    NST_LOG_DEBUG = 1,
    NST_LOG_INFO  = 2,
    NST_LOG_WARN  = 3,
    NST_LOG_ERROR = 4,
    NST_LOG_OFF   = 5,
} nst_log_level;

void nst_log_set_level(nst_log_level level);
nst_log_level nst_log_get_level(void);
/* Разбор "trace|debug|info|warn|error|off"; при неудаче возвращает false. */
bool nst_log_level_parse(const char *name, nst_log_level *out);
const char *nst_log_level_name(nst_log_level level);

/* Куда писать. Файл не закрывается библиотекой; nullptr означает stderr. */
void nst_log_set_stream(FILE *stream);

NST_PRINTF(4, 5)
void nst_log_emit(nst_log_level level, const char *file, int line, const char *fmt, ...);

/* __VA_OPT__ убирает запятую, когда переменных аргументов нет:
 * NST_LOGI("started") и NST_LOGI("port=%d", port) оба корректны. */
#define NST_LOG(level, fmt, ...)                                              \
    do {                                                                      \
        if ((level) >= nst_log_get_level())                                   \
            nst_log_emit((level), __FILE__, __LINE__, (fmt) __VA_OPT__(,) __VA_ARGS__); \
    } while (0)

#define NST_LOGT(fmt, ...) NST_LOG(NST_LOG_TRACE, fmt __VA_OPT__(,) __VA_ARGS__)
#define NST_LOGD(fmt, ...) NST_LOG(NST_LOG_DEBUG, fmt __VA_OPT__(,) __VA_ARGS__)
#define NST_LOGI(fmt, ...) NST_LOG(NST_LOG_INFO,  fmt __VA_OPT__(,) __VA_ARGS__)
#define NST_LOGW(fmt, ...) NST_LOG(NST_LOG_WARN,  fmt __VA_OPT__(,) __VA_ARGS__)
#define NST_LOGE(fmt, ...) NST_LOG(NST_LOG_ERROR, fmt __VA_OPT__(,) __VA_ARGS__)

#endif /* NESTOR_UTIL_LOG_H */
