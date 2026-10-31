/* nestor-bench — нагрузка на встроенную библиотеку и отчёт по задержкам.
 * Меряет put/get напрямую через libnestor, без сети: так видно цену
 * самого хранилища, а не стека TCP. */
#define _POSIX_C_SOURCE 200809L
#include <inttypes.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <nestor/nestor.h>

#include "util/clock.h"
#include "util/log.h"

typedef struct {
    nst_db *db;
    uint64_t ops;
    uint32_t key_space;
    uint32_t value_size;
    unsigned seed;
    int read_percent;
    uint64_t *latencies;   /* нс на операцию */
    uint64_t errors;
} worker_args;

/* xorshift64*: детерминированный и достаточно быстрый, чтобы не быть
 * узким местом бенчмарка (rand() с блокировкой — был бы). */
static uint64_t rng_next(uint64_t *state) {
    uint64_t x = *state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    return x * 0x2545F4914F6CDD1Dull;
}

static void *worker(void *arg) {
    worker_args *w = arg;
    uint64_t rng = w->seed ? w->seed : 1;

    uint8_t *value = malloc(w->value_size);
    if (value == nullptr) return nullptr;
    memset(value, 'v', w->value_size);

    char key[64];
    for (uint64_t i = 0; i < w->ops; i++) {
        uint64_t r = rng_next(&rng);
        int klen = snprintf(key, sizeof key, "key:%010" PRIu64, r % w->key_space);
        nst_slice k = nst_slice_bytes(key, (size_t)klen);

        uint64_t t0 = nst_now_mono_ns();
        nst_status st;
        if ((int)(r % 100) < w->read_percent) {
            nst_slice out;
            st = nst_get(w->db, k, &out);
            if (st == NST_OK) nst_free_value(out);
            else if (st == NST_E_NOTFOUND) st = NST_OK;
        } else {
            st = nst_put(w->db, k, nst_slice_bytes(value, w->value_size));
        }
        w->latencies[i] = nst_now_mono_ns() - t0;
        if (st != NST_OK) w->errors++;
    }
    free(value);
    return nullptr;
}

static int cmp_u64(const void *a, const void *b) {
    uint64_t x = *(const uint64_t *)a, y = *(const uint64_t *)b;
    return (x > y) - (x < y);
}

static uint64_t percentile(const uint64_t *sorted, size_t n, double p) {
    if (n == 0) return 0;
    size_t idx = (size_t)(p * (double)(n - 1));
    return sorted[idx];
}

int main(int argc, char **argv) {
    const char *dir = "./bench-data";
    uint64_t ops = 200000;
    unsigned threads = 4;
    uint32_t key_space = 100000, value_size = 256;
    int read_percent = 50;

    for (int i = 1; i < argc - 1; i++) {
        if (strcmp(argv[i], "--dir") == 0) dir = argv[++i];
        else if (strcmp(argv[i], "--ops") == 0) ops = strtoull(argv[++i], nullptr, 10);
        else if (strcmp(argv[i], "--threads") == 0) threads = (unsigned)strtoul(argv[++i], nullptr, 10);
        else if (strcmp(argv[i], "--keys") == 0) key_space = (uint32_t)strtoul(argv[++i], nullptr, 10);
        else if (strcmp(argv[i], "--value") == 0) value_size = (uint32_t)strtoul(argv[++i], nullptr, 10);
        else if (strcmp(argv[i], "--read-percent") == 0) read_percent = atoi(argv[++i]);
    }
    if (threads == 0) threads = 1;

    nst_log_set_level(NST_LOG_WARN);

    nst_options opts = nst_options_default();
    opts.sync_mode = NST_SYNC_INTERVAL;
    opts.max_segment_bytes = 64u << 20;

    nst_db *db = nullptr;
    nst_status st = nst_open(dir, &opts, &db);
    if (st != NST_OK) {
        fprintf(stderr, "open %s: %s\n", dir, nst_status_str(st));
        return 1;
    }

    uint64_t per_thread = ops / threads;
    pthread_t *tids = calloc(threads, sizeof *tids);
    worker_args *args = calloc(threads, sizeof *args);
    if (tids == nullptr || args == nullptr) return 1;

    for (unsigned t = 0; t < threads; t++) {
        args[t] = (worker_args){
            .db = db, .ops = per_thread, .key_space = key_space,
            .value_size = value_size, .seed = 12345u + t,
            .read_percent = read_percent,
            .latencies = malloc(per_thread * sizeof(uint64_t)),
        };
        if (args[t].latencies == nullptr) return 1;
    }

    uint64_t start = nst_now_mono_ns();
    for (unsigned t = 0; t < threads; t++) pthread_create(&tids[t], nullptr, worker, &args[t]);
    for (unsigned t = 0; t < threads; t++) pthread_join(tids[t], nullptr);
    uint64_t elapsed = nst_now_mono_ns() - start;

    uint64_t total = per_thread * threads, errors = 0;
    uint64_t *all = malloc(total * sizeof(uint64_t));
    if (all == nullptr) return 1;
    for (unsigned t = 0; t < threads; t++) {
        memcpy(all + t * per_thread, args[t].latencies, per_thread * sizeof(uint64_t));
        errors += args[t].errors;
        free(args[t].latencies);
    }
    qsort(all, total, sizeof *all, cmp_u64);

    nst_stats s;
    nst_get_stats(db, &s);

    double secs = (double)elapsed / 1e9;
    printf("операций      %" PRIu64 " (%u потоков, чтений %d%%)\n", total, threads, read_percent);
    printf("время         %.3f с\n", secs);
    printf("пропускная    %.0f оп/с\n", (double)total / secs);
    printf("задержка p50  %.1f мкс\n", (double)percentile(all, total, 0.50) / 1000.0);
    printf("задержка p99  %.1f мкс\n", (double)percentile(all, total, 0.99) / 1000.0);
    printf("задержка p999 %.1f мкс\n", (double)percentile(all, total, 0.999) / 1000.0);
    printf("максимум      %.1f мкс\n", (double)all[total - 1] / 1000.0);
    printf("ключей        %" PRIu64 ", сегментов %" PRIu64 ", на диске %.1f МиБ\n",
           s.keys, s.segments, (double)s.total_bytes / (1024.0 * 1024.0));
    printf("ошибок        %" PRIu64 "\n", errors);

    free(all);
    free(args);
    free(tids);
    nst_close(db);
    return errors == 0 ? 0 : 1;
}
