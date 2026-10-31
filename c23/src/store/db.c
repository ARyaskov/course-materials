#define _GNU_SOURCE
#include <nestor/nestor.h>

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdckdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

#include "store/format.h"
#include "store/hint.h"
#include "store/index.h"
#include "store/record.h"
#include "store/segment.h"
#include "util/arena.h"
#include "util/clock.h"
#include "util/compiler.h"
#include "util/io.h"
#include "util/log.h"
#include "util/slice.h"

/* ------------------------------------------------------------------ */

struct nst_db {
    char dir[3072];   /* + имя файла всегда влезает в NST_PATH_MAX */
    nst_options opts;

    int lock_fd;
    bool closed;

    /* Список сегментов, отсортированный по file_id; последний — активный. */
    nst_segment **segs;
    size_t seg_count;
    size_t seg_cap;
    nst_segment *active;
    uint32_t next_file_id;

    nst_index index;

    pthread_rwlock_t lock;     /* индекс + список сегментов */
    pthread_mutex_t write_mu;  /* сериализует запись в активный сегмент */
    pthread_mutex_t compact_mu;/* один компактор за раз */

    uint64_t seq;              /* под write_mu */
    uint64_t last_sync_ms;     /* под write_mu */

    /* Фоновая компакция. */
    pthread_t compactor;
    bool compactor_running;
    pthread_mutex_t cc_mu;
    pthread_cond_t cc_cv;
    bool stop;

    atomic_uint_least64_t st_puts, st_gets, st_deletes, st_misses;
    atomic_uint_least64_t st_compactions, st_reclaimed, st_fsyncs;
};

const char *nst_version(void) {
    return "1.0.0";
}

nst_options nst_options_default(void) {
    return (nst_options){
        .max_segment_bytes = 256ull << 20,
        .max_key_bytes = NST_MAX_KEY_BYTES,
        .max_value_bytes = 16u << 20,
        .sync_mode = NST_SYNC_INTERVAL,
        .sync_interval_ms = 1000,
        .read_only = false,
        .background_compaction = true,
        .compaction_garbage_ratio = 0.4,
        .compaction_interval_ms = 30000,
    };
}

static void options_normalize(nst_options *o) {
    nst_options d = nst_options_default();
    if (o->max_segment_bytes == 0) o->max_segment_bytes = d.max_segment_bytes;
    if (o->max_segment_bytes > NST_MAX_SEGMENT_BYTES)
        o->max_segment_bytes = NST_MAX_SEGMENT_BYTES;
    if (o->max_key_bytes == 0 || o->max_key_bytes > NST_MAX_KEY_BYTES)
        o->max_key_bytes = NST_MAX_KEY_BYTES;
    if (o->max_value_bytes == 0 || o->max_value_bytes > NST_MAX_VALUE_BYTES)
        o->max_value_bytes = d.max_value_bytes;
    if (o->sync_interval_ms == 0) o->sync_interval_ms = d.sync_interval_ms;
    if (o->compaction_garbage_ratio <= 0.0 || o->compaction_garbage_ratio >= 1.0)
        o->compaction_garbage_ratio = d.compaction_garbage_ratio;
    if (o->compaction_interval_ms == 0)
        o->compaction_interval_ms = d.compaction_interval_ms;
}

/* ------------------------------------------------------------------ */
/* Список сегментов                                                    */

static nst_segment *db_find_segment(const nst_db *db, uint32_t file_id) {
    for (size_t i = 0; i < db->seg_count; i++)
        if (db->segs[i]->file_id == file_id) return db->segs[i];
    return nullptr;
}

static nst_status db_push_segment(nst_db *db, nst_segment *seg) {
    if (db->seg_count == db->seg_cap) {
        size_t cap = db->seg_cap ? db->seg_cap * 2 : 8;
        nst_segment **tmp = realloc(db->segs, cap * sizeof *tmp);
        if (tmp == nullptr) return NST_E_NOMEM;
        db->segs = tmp;
        db->seg_cap = cap;
    }
    db->segs[db->seg_count++] = seg;
    return NST_OK;
}

static void db_drop_segment(nst_db *db, uint32_t file_id) {
    for (size_t i = 0; i < db->seg_count; i++) {
        if (db->segs[i]->file_id != file_id) continue;
        nst_segment_close(db->segs[i]);
        free(db->segs[i]);
        memmove(&db->segs[i], &db->segs[i + 1],
                (db->seg_count - i - 1) * sizeof *db->segs);
        db->seg_count--;
        return;
    }
}

/* ------------------------------------------------------------------ */
/* Восстановление индекса при открытии                                 */

typedef struct {
    nst_db *db;
    nst_segment *seg;
    nst_status st;
} recover_ctx;

/* Общий путь применения записи к индексу: и для hint-файла, и для скана. */
static bool apply_entry(recover_ctx *ctx, nst_slice key, uint64_t offset,
                        uint32_t rec_len, uint64_t seq, uint8_t flags) {
    nst_db *db = ctx->db;
    if (seq > db->seq) db->seq = seq;

    nst_loc old;
    bool had = nst_index_get(&db->index, key, &old);
    if (had && old.seq > seq) return true;   /* уже есть более новая версия */

    if (flags & NST_REC_TOMBSTONE) {
        if (had) {
            nst_segment *s = db_find_segment(db, old.file_id);
            if (s != nullptr && s->live_bytes >= old.rec_len) s->live_bytes -= old.rec_len;
            (void)nst_index_remove(&db->index, key, nullptr);
        }
        return true;
    }

    nst_loc loc = { .offset = offset, .seq = seq,
                    .file_id = ctx->seg->file_id, .rec_len = rec_len };
    bool stored = false;
    nst_status st = nst_index_put(&db->index, key, loc, &stored, nullptr);
    if (st != NST_OK) { ctx->st = st; return false; }
    if (stored) {
        if (had) {
            nst_segment *s = db_find_segment(db, old.file_id);
            if (s != nullptr && s->live_bytes >= old.rec_len) s->live_bytes -= old.rec_len;
        }
        ctx->seg->live_bytes += rec_len;
    }
    return true;
}

static bool hint_cb(nst_slice key, uint64_t offset, uint32_t rec_len, uint64_t seq,
                    uint8_t flags, void *user) {
    return apply_entry(user, key, offset, rec_len, seq, flags);
}

static bool scan_cb(const nst_record *rec, uint64_t offset, uint32_t rec_len, void *user) {
    return apply_entry(user, rec->key, offset, rec_len, rec->seq, rec->flags);
}

static int cmp_u32(const void *a, const void *b) {
    uint32_t x = *(const uint32_t *)a, y = *(const uint32_t *)b;
    return (x > y) - (x < y);
}

static nst_status db_collect_segment_ids(const char *dir, uint32_t **out_ids,
                                         size_t *out_count) {
    DIR *d = opendir(dir);
    if (d == nullptr) return nst_status_from_errno(errno);

    uint32_t *ids = nullptr;
    size_t count = 0, cap = 0;
    nst_status st = NST_OK;

    struct dirent *ent;
    while ((ent = readdir(d)) != nullptr) {
        unsigned id = 0;
        char tail[8] = {};
        /* "%06u.data": sscanf возвращает 2, если совпало и имя подошло целиком. */
        if (sscanf(ent->d_name, "%6u.%4s", &id, tail) != 2) continue;
        if (strcmp(tail, "data") != 0) continue;

        if (count == cap) {
            size_t new_cap = cap ? cap * 2 : 16;
            uint32_t *tmp = realloc(ids, new_cap * sizeof *tmp);
            if (tmp == nullptr) { st = NST_E_NOMEM; goto done; }
            ids = tmp;
            cap = new_cap;
        }
        ids[count++] = (uint32_t)id;
    }
    if (count > 1) qsort(ids, count, sizeof *ids, cmp_u32); /* qsort(nullptr, 0) — UB */

done:
    closedir(d);
    if (st != NST_OK) { free(ids); return st; }
    *out_ids = ids;
    *out_count = count;
    return NST_OK;
}

static nst_status db_recover(nst_db *db) {
    uint32_t *ids = nullptr;
    size_t count = 0;
    NST_TRY(db_collect_segment_ids(db->dir, &ids, &count));

    nst_status st = NST_OK;
    for (size_t i = 0; i < count; i++) {
        bool last = (i + 1 == count);
        bool writable = last && !db->opts.read_only;

        nst_segment *seg = calloc(1, sizeof *seg);
        if (seg == nullptr) { st = NST_E_NOMEM; goto done; }

        st = nst_segment_open(db->dir, ids[i], writable, seg);
        if (st != NST_OK) { free(seg); goto done; }

        st = db_push_segment(db, seg);
        if (st != NST_OK) { nst_segment_close(seg); free(seg); goto done; }

        recover_ctx ctx = { .db = db, .seg = seg, .st = NST_OK };

        /* Быстрый путь: hint-файл. Для активного сегмента его нет —
         * он дописывается после последнего снимка. */
        nst_status hst = last ? NST_E_NOTFOUND
                              : nst_hint_load(db->dir, ids[i], hint_cb, &ctx);
        if (hst == NST_OK && ctx.st == NST_OK) {
            NST_LOGD("segment %06" PRIu32 " restored from hint", ids[i]);
            continue;
        }
        if (ctx.st != NST_OK) { st = ctx.st; goto done; }

        uint64_t valid_end = 0;
        ctx = (recover_ctx){ .db = db, .seg = seg, .st = NST_OK };
        st = nst_segment_scan(seg, scan_cb, &ctx, &valid_end);
        if (st == NST_OK) st = ctx.st;
        if (st != NST_OK) goto done;

        if (valid_end < nst_segment_size(seg)) {
            /* Хвост не дописался при падении. Для активного сегмента
             * усекаем, для остальных — сообщаем и продолжаем читать. */
            NST_LOGW("segment %06" PRIu32 ": %" PRIu64 " bytes of damaged tail",
                     ids[i], nst_segment_size(seg) - valid_end);
            if (writable) {
                st = nst_segment_truncate(seg, valid_end);
                if (st != NST_OK) goto done;
            }
        }
    }

    db->next_file_id = count > 0 ? ids[count - 1] + 1 : 1;
    if (count > 0 && !db->opts.read_only) db->active = db->segs[count - 1];

done:
    free(ids);
    return st;
}

/* ------------------------------------------------------------------ */
/* Блокировка каталога                                                 */

static nst_status db_lock_dir(nst_db *db) {
    char path[4096];
    snprintf(path, sizeof path, "%s/LOCK", db->dir);
    int fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0644);
    if (fd < 0) return nst_status_from_errno(errno);

    if (flock(fd, LOCK_EX | LOCK_NB) != 0) {
        nst_close_fd(&fd);
        return NST_E_LOCKED;
    }
    /* Пишем pid держателя: полезно, когда вторая копия не смогла стартовать. */
    char pid[32];
    int n = snprintf(pid, sizeof pid, "%ld\n", (long)getpid());
    if (ftruncate(fd, 0) != 0 || nst_pwrite_full(fd, pid, (size_t)n, 0) != NST_OK)
        NST_LOGW("не удалось записать pid в LOCK: %s", strerror(errno));
    db->lock_fd = fd;
    return NST_OK;
}

/* ------------------------------------------------------------------ */

static void *compactor_main(void *arg);

static nst_status db_rotate_locked(nst_db *db);

nst_status nst_open(const char *dir, const nst_options *opts, nst_db **out) {
    if (dir == nullptr || out == nullptr) return NST_E_INVAL;

    nst_db *db = calloc(1, sizeof *db);
    if (db == nullptr) return NST_E_NOMEM;

    db->lock_fd = -1;
    db->opts = opts ? *opts : nst_options_default();
    options_normalize(&db->opts);
    if (snprintf(db->dir, sizeof db->dir, "%s", dir) >= (int)sizeof db->dir) {
        free(db);
        return NST_E_INVAL;
    }

    nst_status st = NST_OK;
    if (mkdir(db->dir, 0755) != 0 && errno != EEXIST) {
        st = nst_status_from_errno(errno);
        goto fail;
    }

    pthread_rwlock_init(&db->lock, nullptr);
    pthread_mutex_init(&db->write_mu, nullptr);
    pthread_mutex_init(&db->compact_mu, nullptr);
    pthread_mutex_init(&db->cc_mu, nullptr);
    pthread_cond_init(&db->cc_cv, nullptr);

    if (!db->opts.read_only) NST_TRY_GOTO(db_lock_dir(db), fail_sync);
    NST_TRY_GOTO(nst_index_init(&db->index, 1024), fail_sync);
    NST_TRY_GOTO(db_recover(db), fail_sync);

    if (db->active == nullptr && !db->opts.read_only)
        NST_TRY_GOTO(db_rotate_locked(db), fail_sync);

    db->last_sync_ms = nst_now_wall_ms();

    if (db->opts.background_compaction && !db->opts.read_only) {
        if (pthread_create(&db->compactor, nullptr, compactor_main, db) == 0)
            db->compactor_running = true;
        else
            NST_LOGW("failed to start compaction thread, running without it");
    }

    NST_LOGI("opened %s: %zu segments, %zu keys, seq=%" PRIu64,
             db->dir, db->seg_count, nst_index_count(&db->index), db->seq);
    *out = db;
    return NST_OK;

fail_sync:
    for (size_t i = 0; i < db->seg_count; i++) {
        nst_segment_close(db->segs[i]);
        free(db->segs[i]);
    }
    free(db->segs);
    nst_index_destroy(&db->index);
    nst_close_fd(&db->lock_fd);
    pthread_cond_destroy(&db->cc_cv);
    pthread_mutex_destroy(&db->cc_mu);
    pthread_mutex_destroy(&db->compact_mu);
    pthread_mutex_destroy(&db->write_mu);
    pthread_rwlock_destroy(&db->lock);
fail:
    free(db);
    return st;
}

void nst_close(nst_db *db) {
    if (db == nullptr) return;

    if (db->compactor_running) {
        pthread_mutex_lock(&db->cc_mu);
        db->stop = true;
        pthread_cond_broadcast(&db->cc_cv);
        pthread_mutex_unlock(&db->cc_mu);
        pthread_join(db->compactor, nullptr);
        db->compactor_running = false;
    }

    if (db->active != nullptr && !db->opts.read_only) {
        if (nst_fsync_fd(db->active->fd) != NST_OK)
            NST_LOGE("final fsync failed for segment %06" PRIu32, db->active->file_id);
    }

    for (size_t i = 0; i < db->seg_count; i++) {
        nst_segment_close(db->segs[i]);
        free(db->segs[i]);
    }
    free(db->segs);
    nst_index_destroy(&db->index);
    nst_close_fd(&db->lock_fd);

    pthread_cond_destroy(&db->cc_cv);
    pthread_mutex_destroy(&db->cc_mu);
    pthread_mutex_destroy(&db->compact_mu);
    pthread_mutex_destroy(&db->write_mu);
    pthread_rwlock_destroy(&db->lock);
    free(db);
}

/* ------------------------------------------------------------------ */
/* Запись                                                              */

/* Создать новый активный сегмент. Вызывается под write_mu; список
 * сегментов меняется под write-блокировкой. */
static nst_status db_rotate_locked(nst_db *db) {
    nst_segment *seg = calloc(1, sizeof *seg);
    if (seg == nullptr) return NST_E_NOMEM;

    nst_status st = nst_segment_create(db->dir, db->next_file_id, seg);
    if (st != NST_OK) { free(seg); return st; }

    pthread_rwlock_wrlock(&db->lock);
    st = db_push_segment(db, seg);
    if (st == NST_OK) {
        db->active = seg;
        db->next_file_id++;
    }
    pthread_rwlock_unlock(&db->lock);

    if (st != NST_OK) { nst_segment_close(seg); free(seg); return st; }

    st = nst_fsync_dir(db->dir);   /* имя нового файла должно пережить сбой */
    NST_LOGD("rotated to segment %06" PRIu32, seg->file_id);
    return st;
}

static nst_status db_maybe_sync(nst_db *db, bool force) {
    if (db->active == nullptr) return NST_OK;
    bool need = force || db->opts.sync_mode == NST_SYNC_ALWAYS;
    if (!need && db->opts.sync_mode == NST_SYNC_INTERVAL) {
        uint64_t now = nst_now_wall_ms();
        need = now - db->last_sync_ms >= db->opts.sync_interval_ms;
        if (need) db->last_sync_ms = now;
    }
    if (!need) return NST_OK;
    NST_TRY(nst_fsync_fd(db->active->fd));
    atomic_fetch_add_explicit(&db->st_fsyncs, 1, memory_order_relaxed);
    return NST_OK;
}

/* Общий путь для put и delete. */
static nst_status db_append(nst_db *db, nst_slice key, nst_slice value, uint8_t flags) {
    if (db->opts.read_only) return NST_E_INVAL;
    if (key.len == 0 || key.len > db->opts.max_key_bytes) return NST_E_INVAL;
    if (value.len > db->opts.max_value_bytes) return NST_E_TOOBIG;

    size_t total;
    if (!nst_record_size(key.len, value.len, &total)) return NST_E_TOOBIG;

    uint8_t stack_buf[4096];
    uint8_t *buf = stack_buf;
    uint8_t *heap = nullptr;
    if (total > sizeof stack_buf) {
        heap = malloc(total);
        if (heap == nullptr) return NST_E_NOMEM;
        buf = heap;
    }

    pthread_mutex_lock(&db->write_mu);

    nst_status st = NST_OK;
    if (db->active == nullptr) { st = NST_E_CLOSED; goto unlock; }

    if (nst_segment_size(db->active) + total > db->opts.max_segment_bytes) {
        /* Перед ротацией сохраняем hint для закрываемого сегмента:
         * следующий старт не будет читать его целиком. */
        st = db_maybe_sync(db, true);
        if (st != NST_OK) goto unlock;
        st = db_rotate_locked(db);
        if (st != NST_OK) goto unlock;
    }

    nst_record rec = {
        .key = key, .value = value, .seq = db->seq + 1,
        .timestamp_ms = nst_now_wall_ms(), .flags = flags,
    };

    size_t written = 0;
    st = nst_record_encode(&rec, buf, total, &written);
    if (st != NST_OK) goto unlock;

    uint64_t offset = 0;
    st = nst_segment_append(db->active, buf, written, &offset);
    if (st != NST_OK) goto unlock;

    db->seq = rec.seq;

    nst_loc loc = { .offset = offset, .seq = rec.seq,
                    .file_id = db->active->file_id, .rec_len = (uint32_t)written };

    pthread_rwlock_wrlock(&db->lock);
    nst_loc old = {};
    bool had = nst_index_get(&db->index, key, &old);

    if (flags & NST_REC_TOMBSTONE) {
        if (had) {
            nst_segment *s = db_find_segment(db, old.file_id);
            if (s && s->live_bytes >= old.rec_len) s->live_bytes -= old.rec_len;
            (void)nst_index_remove(&db->index, key, nullptr);
        } else {
            st = NST_E_NOTFOUND;
        }
    } else {
        bool stored = false;
        st = nst_index_put(&db->index, key, loc, &stored, nullptr);
        if (st == NST_OK && stored) {
            if (had) {
                nst_segment *s = db_find_segment(db, old.file_id);
                if (s && s->live_bytes >= old.rec_len) s->live_bytes -= old.rec_len;
            }
            db->active->live_bytes += written;
        }
    }
    pthread_rwlock_unlock(&db->lock);

    /* Надгробие для отсутствующего ключа уже записано в лог — это не ошибка
     * записи, а сообщение вызывающей стороне. Данные на диске консистентны. */
    nst_status sync_st = db_maybe_sync(db, false);
    if (st == NST_OK) st = sync_st;

unlock:
    pthread_mutex_unlock(&db->write_mu);
    free(heap);
    return st;
}

nst_status nst_put(nst_db *db, nst_slice key, nst_slice value) {
    if (db == nullptr) return NST_E_INVAL;
    if (value.ptr == nullptr && value.len > 0) return NST_E_INVAL;
    atomic_fetch_add_explicit(&db->st_puts, 1, memory_order_relaxed);
    return db_append(db, key, value, NST_REC_NONE);
}

nst_status nst_delete(nst_db *db, nst_slice key) {
    if (db == nullptr) return NST_E_INVAL;
    atomic_fetch_add_explicit(&db->st_deletes, 1, memory_order_relaxed);
    return db_append(db, key, (nst_slice){}, NST_REC_TOMBSTONE);
}

nst_status nst_sync(nst_db *db) {
    if (db == nullptr) return NST_E_INVAL;
    pthread_mutex_lock(&db->write_mu);
    nst_status st = db_maybe_sync(db, true);
    pthread_mutex_unlock(&db->write_mu);
    return st;
}

/* ------------------------------------------------------------------ */
/* Чтение                                                              */

nst_status nst_get(nst_db *db, nst_slice key, nst_slice *out) {
    if (db == nullptr || out == nullptr || key.len == 0) return NST_E_INVAL;
    atomic_fetch_add_explicit(&db->st_gets, 1, memory_order_relaxed);

    pthread_rwlock_rdlock(&db->lock);

    nst_loc loc;
    nst_status st;
    if (!nst_index_get(&db->index, key, &loc)) {
        st = NST_E_NOTFOUND;
        goto unlock;
    }

    nst_segment *seg = db_find_segment(db, loc.file_id);
    if (seg == nullptr) { st = NST_E_CORRUPT; goto unlock; }

    uint8_t *buf = nullptr;
    nst_record rec;
    st = nst_segment_read_record(seg, loc.offset, loc.rec_len, &buf, &rec);
    if (st != NST_OK) goto unlock;

    if (!nst_slice_eq(rec.key, key)) {   /* индекс разошёлся с диском */
        free(buf);
        st = NST_E_CORRUPT;
        goto unlock;
    }

    st = nst_slice_dup(rec.value, out);
    free(buf);

unlock:
    pthread_rwlock_unlock(&db->lock);
    if (st == NST_E_NOTFOUND)
        atomic_fetch_add_explicit(&db->st_misses, 1, memory_order_relaxed);
    return st;
}

bool nst_contains(nst_db *db, nst_slice key) {
    if (db == nullptr || key.len == 0) return false;
    pthread_rwlock_rdlock(&db->lock);
    bool found = nst_index_get(&db->index, key, nullptr);
    pthread_rwlock_unlock(&db->lock);
    return found;
}

typedef struct {
    nst_scan_fn fn;
    void *user;
} scan_ctx;

static bool scan_adapter(nst_slice key, nst_loc loc, void *user) {
    (void)loc;
    scan_ctx *ctx = user;
    return ctx->fn(key, ctx->user);
}

nst_status nst_scan(nst_db *db, nst_scan_fn fn, void *user) {
    if (db == nullptr || fn == nullptr) return NST_E_INVAL;
    scan_ctx ctx = { .fn = fn, .user = user };
    pthread_rwlock_rdlock(&db->lock);
    nst_index_foreach(&db->index, scan_adapter, &ctx);
    pthread_rwlock_unlock(&db->lock);
    return NST_OK;
}

void nst_get_stats(nst_db *db, nst_stats *out) {
    if (db == nullptr || out == nullptr) return;
    *out = (nst_stats){};

    pthread_rwlock_rdlock(&db->lock);
    out->keys = nst_index_count(&db->index);
    out->segments = db->seg_count;
    for (size_t i = 0; i < db->seg_count; i++) {
        out->total_bytes += nst_segment_size(db->segs[i]);
        out->live_bytes += db->segs[i]->live_bytes;
    }
    pthread_rwlock_unlock(&db->lock);

    out->puts = atomic_load_explicit(&db->st_puts, memory_order_relaxed);
    out->gets = atomic_load_explicit(&db->st_gets, memory_order_relaxed);
    out->deletes = atomic_load_explicit(&db->st_deletes, memory_order_relaxed);
    out->get_misses = atomic_load_explicit(&db->st_misses, memory_order_relaxed);
    out->compactions = atomic_load_explicit(&db->st_compactions, memory_order_relaxed);
    out->reclaimed_bytes = atomic_load_explicit(&db->st_reclaimed, memory_order_relaxed);
    out->fsyncs = atomic_load_explicit(&db->st_fsyncs, memory_order_relaxed);
}

/* ------------------------------------------------------------------ */
/* Компакция                                                           */

typedef struct {
    nst_slice key;      /* копия ключа в арене */
    nst_loc loc;        /* расположение на момент снимка */
    uint64_t new_off;
    uint32_t new_len;
    uint8_t flags;
    bool committed;
} merge_ent;

typedef struct {
    nst_arena *arena;
    merge_ent *items;
    size_t count, cap;
    uint32_t active_id;   /* сегмент, который не участвует в слиянии */
    bool oom;
} collect_ctx;

static bool collect_cb(nst_slice key, nst_loc loc, void *user) {
    collect_ctx *c = user;
    if (loc.file_id == c->active_id) return true;

    if (c->count == c->cap) {
        size_t cap = c->cap ? c->cap * 2 : 256;
        merge_ent *tmp = realloc(c->items, cap * sizeof *tmp);
        if (tmp == nullptr) { c->oom = true; return false; }
        c->items = tmp;
        c->cap = cap;
    }
    void *key_copy = nst_arena_memdup(c->arena, key.ptr, key.len);
    if (key_copy == nullptr) { c->oom = true; return false; }

    c->items[c->count++] = (merge_ent){
        .key = { .ptr = key_copy, .len = key.len },
        .loc = loc,
    };
    return true;
}

/* Прочитать запись как есть, без разбора: при слиянии мы переносим байты
 * вместе с CRC и номером версии. */
static nst_status read_raw(nst_db *db, nst_loc loc, uint8_t *dst) {
    nst_segment *seg = db_find_segment(db, loc.file_id);
    if (seg == nullptr) return NST_E_CORRUPT;
    return nst_pread_full(seg->fd, dst, loc.rec_len, (off_t)loc.offset);
}

static nst_status db_insert_before_active(nst_db *db, nst_segment *seg) {
    NST_TRY(db_push_segment(db, seg));
    /* Инвариант списка: id возрастают, активный сегмент последний. */
    for (size_t i = db->seg_count - 1; i > 0; i--) {
        if (db->segs[i - 1]->file_id < seg->file_id) break;
        nst_segment *tmp = db->segs[i - 1];
        db->segs[i - 1] = db->segs[i];
        db->segs[i] = tmp;
    }
    return NST_OK;
}

/* Записать hint-файл для сегмента по текущему состоянию индекса. */
typedef struct {
    nst_hint_writer *w;
    uint32_t file_id;
    nst_status st;
} hint_dump_ctx;

static bool hint_dump_cb(nst_slice key, nst_loc loc, void *user) {
    hint_dump_ctx *c = user;
    if (loc.file_id != c->file_id) return true;
    c->st = nst_hint_writer_add(c->w, key, loc.offset, loc.rec_len, loc.seq, NST_REC_NONE);
    return c->st == NST_OK;
}

static nst_status db_write_hint(nst_db *db, uint32_t file_id) {
    nst_hint_writer w;
    NST_TRY(nst_hint_writer_init(&w, file_id));

    hint_dump_ctx ctx = { .w = &w, .file_id = file_id, .st = NST_OK };
    pthread_rwlock_rdlock(&db->lock);
    nst_index_foreach(&db->index, hint_dump_cb, &ctx);
    pthread_rwlock_unlock(&db->lock);

    nst_status st = ctx.st;
    if (st == NST_OK) st = nst_hint_writer_commit(&w, db->dir);
    nst_hint_writer_free(&w);
    return st;
}

static bool hint_exists(const nst_db *db, uint32_t file_id) {
    char name[32], path[4096];
    nst_segment_name(name, file_id, "hint");
    snprintf(path, sizeof path, "%s/%s", db->dir, name);
    struct stat sb;
    return stat(path, &sb) == 0;
}

/* Доля мусора среди неактивных сегментов. */
static double db_garbage_ratio(nst_db *db, size_t *immutable_count) {
    uint64_t total = 0, live = 0;
    size_t n = 0;
    pthread_rwlock_rdlock(&db->lock);
    for (size_t i = 0; i < db->seg_count; i++) {
        if (db->segs[i] == db->active) continue;
        total += nst_segment_size(db->segs[i]);
        live += db->segs[i]->live_bytes;
        n++;
    }
    pthread_rwlock_unlock(&db->lock);
    if (immutable_count) *immutable_count = n;
    if (total == 0) return 0.0;
    return (double)(total - live) / (double)total;
}

static nst_status db_compact_locked(nst_db *db) {
    /* 1. Резервируем id для сливаемого сегмента и делаем ротацию, чтобы
     *    он оказался раньше нового активного: инвариант «активный —
     *    последний» должен сохраниться и после перезапуска. */
    pthread_mutex_lock(&db->write_mu);
    uint32_t merge_id = db->next_file_id++;
    uint32_t old_active_id = db->active ? db->active->file_id : 0;
    nst_status st = db_rotate_locked(db);
    pthread_mutex_unlock(&db->write_mu);
    if (st != NST_OK) return st;
    (void)old_active_id;

    uint32_t active_id = db->active->file_id;

    /* 2. Снимок живых записей всех неактивных сегментов. */
    nst_arena arena;
    nst_arena_init(&arena, 256u * 1024u);
    collect_ctx cc = { .arena = &arena, .active_id = active_id };

    pthread_rwlock_rdlock(&db->lock);
    nst_index_foreach(&db->index, collect_cb, &cc);
    uint64_t before_bytes = 0;
    for (size_t i = 0; i < db->seg_count; i++)
        if (db->segs[i] != db->active) before_bytes += nst_segment_size(db->segs[i]);
    pthread_rwlock_unlock(&db->lock);

    if (cc.oom) { st = NST_E_NOMEM; goto cleanup; }

    /* 3. Переносим байты в новый сегмент, не мешая читателям и писателям. */
    nst_segment *merged = calloc(1, sizeof *merged);
    if (merged == nullptr) { st = NST_E_NOMEM; goto cleanup; }
    st = nst_segment_create(db->dir, merge_id, merged);
    if (st != NST_OK) { free(merged); goto cleanup; }

    for (size_t i = 0; i < cc.count; i++) {
        merge_ent *e = &cc.items[i];
        uint8_t *buf = malloc(e->loc.rec_len);
        if (buf == nullptr) { st = NST_E_NOMEM; break; }

        pthread_rwlock_rdlock(&db->lock);
        st = read_raw(db, e->loc, buf);
        pthread_rwlock_unlock(&db->lock);
        if (st != NST_OK) { free(buf); break; }

        uint64_t off = 0;
        st = nst_segment_append(merged, buf, e->loc.rec_len, &off);
        free(buf);
        if (st != NST_OK) break;

        e->new_off = off;
        e->new_len = e->loc.rec_len;
    }
    if (st == NST_OK) st = nst_fsync_fd(merged->fd);
    if (st != NST_OK) {
        char name[32], path[4096];
        nst_segment_name(name, merge_id, "data");
        snprintf(path, sizeof path, "%s/%s", db->dir, name);
        nst_segment_close(merged);
        free(merged);
        (void)unlink(path);
        goto cleanup;
    }

    /* 4. Переключаем индекс на новый сегмент. Записи, которые за время
     *    слияния успели перезаписать, оставляем как есть. */
    uint64_t committed_bytes = 0;
    pthread_rwlock_wrlock(&db->lock);
    st = db_insert_before_active(db, merged);
    if (st == NST_OK) {
        for (size_t i = 0; i < cc.count; i++) {
            merge_ent *e = &cc.items[i];
            nst_loc cur;
            if (!nst_index_get(&db->index, e->key, &cur)) continue;
            if (cur.file_id != e->loc.file_id || cur.offset != e->loc.offset) continue;

            nst_loc fresh = { .offset = e->new_off, .seq = e->loc.seq,
                              .file_id = merge_id, .rec_len = e->new_len };
            bool stored = false;
            if (nst_index_put(&db->index, e->key, fresh, &stored, nullptr) == NST_OK && stored) {
                e->committed = true;
                committed_bytes += e->new_len;
            }
        }
        merged->live_bytes = committed_bytes;

        /* 5. Старые сегменты больше никому не нужны. */
        uint32_t *doomed = malloc(db->seg_count * sizeof *doomed);
        size_t doomed_n = 0;
        if (doomed != nullptr) {
            for (size_t i = 0; i < db->seg_count; i++) {
                nst_segment *s = db->segs[i];
                if (s == db->active || s == merged) continue;
                doomed[doomed_n++] = s->file_id;
            }
            for (size_t i = 0; i < doomed_n; i++) db_drop_segment(db, doomed[i]);
        }
        pthread_rwlock_unlock(&db->lock);

        for (size_t i = 0; i < doomed_n; i++) {
            char name[32], path[4096];
            nst_segment_name(name, doomed[i], "data");
            snprintf(path, sizeof path, "%s/%s", db->dir, name);
            (void)unlink(path);
            nst_hint_remove(db->dir, doomed[i]);
        }
        free(doomed);
        (void)nst_fsync_dir(db->dir);
    } else {
        pthread_rwlock_unlock(&db->lock);
        nst_segment_close(merged);
        free(merged);
        goto cleanup;
    }

    if (db_write_hint(db, merge_id) != NST_OK)
        NST_LOGW("hint file for segment %06" PRIu32 " not written", merge_id);

    uint64_t merged_size = nst_segment_size(merged);
    uint64_t reclaimed = before_bytes > merged_size ? before_bytes - merged_size : 0;
    atomic_fetch_add_explicit(&db->st_compactions, 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&db->st_reclaimed, reclaimed, memory_order_relaxed);
    NST_LOGI("compacted %zu records into segment %06" PRIu32 ", reclaimed %" PRIu64 " bytes",
             cc.count, merge_id, reclaimed);

cleanup:
    free(cc.items);
    nst_arena_destroy(&arena);
    return st;
}

nst_status nst_compact(nst_db *db) {
    if (db == nullptr) return NST_E_INVAL;
    if (db->opts.read_only) return NST_E_INVAL;

    pthread_mutex_lock(&db->compact_mu);
    nst_status st = db_compact_locked(db);
    pthread_mutex_unlock(&db->compact_mu);
    return st;
}

static void compactor_maintain_hints(nst_db *db) {
    uint32_t ids[64];
    size_t n = 0;
    pthread_rwlock_rdlock(&db->lock);
    for (size_t i = 0; i < db->seg_count && n < NST_ARRAY_LEN(ids); i++)
        if (db->segs[i] != db->active) ids[n++] = db->segs[i]->file_id;
    pthread_rwlock_unlock(&db->lock);

    for (size_t i = 0; i < n; i++) {
        if (hint_exists(db, ids[i])) continue;
        if (db_write_hint(db, ids[i]) == NST_OK)
            NST_LOGD("hint written for segment %06" PRIu32, ids[i]);
    }
}

static void *compactor_main(void *arg) {
    nst_db *db = arg;
    pthread_setname_np(pthread_self(), "nst-compact");

    for (;;) {
        struct timespec deadline;
        clock_gettime(CLOCK_REALTIME, &deadline);
        uint64_t ns = (uint64_t)deadline.tv_nsec +
                      (uint64_t)db->opts.compaction_interval_ms * 1000000u;
        deadline.tv_sec += (time_t)(ns / 1000000000u);
        deadline.tv_nsec = (long)(ns % 1000000000u);

        pthread_mutex_lock(&db->cc_mu);
        while (!db->stop) {
            if (pthread_cond_timedwait(&db->cc_cv, &db->cc_mu, &deadline) == ETIMEDOUT)
                break;
        }
        bool stop = db->stop;
        pthread_mutex_unlock(&db->cc_mu);
        if (stop) break;

        compactor_maintain_hints(db);

        size_t immutable = 0;
        double ratio = db_garbage_ratio(db, &immutable);
        if (immutable >= 1 && ratio >= db->opts.compaction_garbage_ratio) {
            NST_LOGI("starting compaction: %zu immutable segments, garbage %.0f%%",
                     immutable, ratio * 100.0);
            nst_status st = nst_compact(db);
            if (st != NST_OK) NST_LOGE("compaction failed: %s", nst_status_str(st));
        }
    }
    return nullptr;
}
