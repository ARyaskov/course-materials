/* nestord — сетевой сервер поверх libnestor. */
#define _GNU_SOURCE
#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <nestor/nestor.h>

#include "net/server.h"
#include "util/log.h"

/* Разбор размеров вида 512, 64K, 256M, 2G. */
static bool parse_size(const char *s, uint64_t *out) {
    errno = 0;
    char *end = nullptr;
    unsigned long long v = strtoull(s, &end, 10);
    if (end == s || errno == ERANGE) return false;

    uint64_t mult = 1;
    switch (*end) {
        case 'k': case 'K': mult = 1ull << 10; end++; break;
        case 'm': case 'M': mult = 1ull << 20; end++; break;
        case 'g': case 'G': mult = 1ull << 30; end++; break;
        case '\0': break;
        default: return false;
    }
    if (*end != '\0') return false;
    if (v > UINT64_MAX / mult) return false;
    *out = (uint64_t)v * mult;
    return true;
}

static bool parse_sync_mode(const char *s, nst_sync_mode *out) {
    if (strcmp(s, "never") == 0)    { *out = NST_SYNC_NEVER; return true; }
    if (strcmp(s, "interval") == 0) { *out = NST_SYNC_INTERVAL; return true; }
    if (strcmp(s, "always") == 0)   { *out = NST_SYNC_ALWAYS; return true; }
    return false;
}

[[noreturn]] static void usage(const char *argv0, int code) {
    fprintf(code == 0 ? stdout : stderr,
        "nestord %s — key-value сервер\n\n"
        "Использование: %s --dir PATH [опции]\n\n"
        "  --dir PATH             каталог данных (обязателен)\n"
        "  --host HOST            интерфейс (по умолчанию все)\n"
        "  --port N               TCP-порт (7717)\n"
        "  --unix PATH            дополнительно слушать unix-сокет\n"
        "  --segment-size SIZE    размер сегмента (256M)\n"
        "  --max-value SIZE       предел значения (16M)\n"
        "  --sync never|interval|always   политика fsync (interval)\n"
        "  --sync-interval MS     период fsync (1000)\n"
        "  --max-connections N    предел соединений (1024)\n"
        "  --no-compaction        не запускать фоновую компакцию\n"
        "  --log-level LEVEL      trace|debug|info|warn|error (info)\n"
        "  --version, --help\n",
        nst_version(), argv0);
    exit(code);
}

int main(int argc, char **argv) {
    const char *dir = nullptr;
    nst_options opts = nst_options_default();
    nst_server_config cfg = { .port = 7717 };

    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        const char *next = (i + 1 < argc) ? argv[i + 1] : nullptr;

        if (strcmp(a, "--help") == 0) usage(argv[0], 0);
        if (strcmp(a, "--version") == 0) { printf("nestord %s\n", nst_version()); return 0; }
        if (strcmp(a, "--no-compaction") == 0) { opts.background_compaction = false; continue; }

        if (next == nullptr) { fprintf(stderr, "нет значения для %s\n", a); return 2; }
        i++;

        uint64_t size = 0;
        if (strcmp(a, "--dir") == 0) dir = next;
        else if (strcmp(a, "--host") == 0) cfg.host = next;
        else if (strcmp(a, "--unix") == 0) cfg.unix_path = next;
        else if (strcmp(a, "--port") == 0) cfg.port = (uint16_t)strtoul(next, nullptr, 10);
        else if (strcmp(a, "--max-connections") == 0)
            cfg.max_connections = (uint32_t)strtoul(next, nullptr, 10);
        else if (strcmp(a, "--sync-interval") == 0)
            opts.sync_interval_ms = (uint32_t)strtoul(next, nullptr, 10);
        else if (strcmp(a, "--segment-size") == 0) {
            if (!parse_size(next, &size)) { fprintf(stderr, "плохой размер: %s\n", next); return 2; }
            opts.max_segment_bytes = size;
        } else if (strcmp(a, "--max-value") == 0) {
            if (!parse_size(next, &size)) { fprintf(stderr, "плохой размер: %s\n", next); return 2; }
            opts.max_value_bytes = (uint32_t)size;
        } else if (strcmp(a, "--sync") == 0) {
            if (!parse_sync_mode(next, &opts.sync_mode)) { fprintf(stderr, "плохой режим: %s\n", next); return 2; }
        } else if (strcmp(a, "--log-level") == 0) {
            nst_log_level lvl;
            if (!nst_log_level_parse(next, &lvl)) { fprintf(stderr, "плохой уровень: %s\n", next); return 2; }
            nst_log_set_level(lvl);
        } else {
            fprintf(stderr, "неизвестная опция: %s\n", a);
            usage(argv[0], 2);
        }
    }

    if (dir == nullptr) usage(argv[0], 2);

    /* До создания потоков: nst_open поднимет поток компакции, и он
     * унаследует маску. Иначе SIGTERM достанется ему и убьёт процесс. */
    if (nst_server_block_signals() != NST_OK) {
        fprintf(stderr, "не удалось заблокировать сигналы\n");
        return 1;
    }

    nst_db *db = nullptr;
    nst_status st = nst_open(dir, &opts, &db);
    if (st != NST_OK) {
        fprintf(stderr, "не удалось открыть %s: %s\n", dir, nst_status_str(st));
        return 1;
    }

    nst_server *srv = nullptr;
    st = nst_server_create(db, &cfg, &srv);
    if (st != NST_OK) {
        fprintf(stderr, "не удалось запустить сервер: %s\n", nst_status_str(st));
        nst_close(db);
        return 1;
    }

    st = nst_server_run(srv);
    nst_server_destroy(srv);

    /* Порядок остановки важен: сначала сеть, потом хранилище —
     * иначе последние ответы уйдут клиенту раньше, чем данные лягут на диск. */
    nst_close(db);

    if (st != NST_OK) {
        fprintf(stderr, "сервер завершился с ошибкой: %s\n", nst_status_str(st));
        return 1;
    }
    return 0;
}
