#define _GNU_SOURCE
#include "util/log.h"

#include <stdarg.h>
#include <stdatomic.h>
#include <string.h>
#include <unistd.h>
#include <sys/syscall.h>

#include "util/clock.h"

static atomic_uchar g_level = NST_LOG_INFO;
static FILE *g_stream = nullptr;

void nst_log_set_level(nst_log_level level) {
    atomic_store_explicit(&g_level, (unsigned char)level, memory_order_relaxed);
}

nst_log_level nst_log_get_level(void) {
    return (nst_log_level)atomic_load_explicit(&g_level, memory_order_relaxed);
}

void nst_log_set_stream(FILE *stream) { g_stream = stream; }

static const char *const k_names[] = {
    [NST_LOG_TRACE] = "TRACE", [NST_LOG_DEBUG] = "DEBUG",
    [NST_LOG_INFO]  = "INFO",  [NST_LOG_WARN]  = "WARN",
    [NST_LOG_ERROR] = "ERROR", [NST_LOG_OFF]   = "OFF",
};
static_assert(sizeof k_names / sizeof k_names[0] == NST_LOG_OFF + 1,
              "таблица имён уровней разошлась с enum");

const char *nst_log_level_name(nst_log_level level) {
    return (level <= NST_LOG_OFF) ? k_names[level] : "?";
}

bool nst_log_level_parse(const char *name, nst_log_level *out) {
    if (name == nullptr || out == nullptr) return false;
    for (unsigned i = 0; i <= NST_LOG_OFF; i++) {
        if (strcasecmp(name, k_names[i]) == 0) { *out = (nst_log_level)i; return true; }
    }
    return false;
}

static long current_tid(void) {
#if defined(SYS_gettid)
    return syscall(SYS_gettid);
#else
    return 0;
#endif
}

/* Базовое имя файла без каталогов: __FILE__ в CMake бывает абсолютным. */
static const char *short_file(const char *path) {
    const char *slash = strrchr(path, '/');
    return slash ? slash + 1 : path;
}

void nst_log_emit(nst_log_level level, const char *file, int line, const char *fmt, ...) {
    FILE *out = g_stream ? g_stream : stderr;
    char ts[32];
    nst_format_time_ms(nst_now_wall_ms(), ts);

    char msg[1024];
    va_list ap;
    va_start(ap);
    int n = vsnprintf(msg, sizeof msg, fmt, ap);
    va_end(ap);
    if (n < 0) return;

    /* Одна fprintf-строка вместо нескольких: меньше шансов перемешать
     * вывод из разных потоков. */
    fprintf(out, "%s %-5s [tid %ld] %s:%d %s\n",
            ts, nst_log_level_name(level), current_tid(), short_file(file), line, msg);
    if (level >= NST_LOG_WARN) fflush(out);
}
