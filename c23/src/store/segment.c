#define _GNU_SOURCE
#include "store/segment.h"

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "store/format.h"
#include "util/clock.h"
#include "util/compiler.h"
#include "util/endian.h"
#include "util/io.h"
#include "util/log.h"

void nst_segment_name(char buf[static 32], uint32_t file_id, const char *ext) {
    snprintf(buf, 32, "%06" PRIu32 ".%s", file_id, ext);
}

static void seg_path(char buf[static 4096], const char *dir, uint32_t file_id,
                     const char *ext) {
    char name[32];
    nst_segment_name(name, file_id, ext);
    snprintf(buf, 4096, "%s/%s", dir, name);
}

static void encode_seg_header(uint8_t hdr[static NST_SEG_HDR_SIZE], uint32_t file_id,
                              uint64_t created_ms) {
    memset(hdr, 0, NST_SEG_HDR_SIZE);
    memcpy(hdr, NST_SEG_MAGIC, sizeof NST_SEG_MAGIC);
    nst_store_le32(hdr + 8, NST_FORMAT_VERSION);
    nst_store_le32(hdr + 12, 0);
    nst_store_le64(hdr + 16, file_id);
    nst_store_le64(hdr + 24, created_ms);
}

nst_status nst_segment_create(const char *dir, uint32_t file_id, nst_segment *out) {
    char path[4096];
    seg_path(path, dir, file_id, "data");

    /* O_EXCL: если файл уже есть, значит логика выбора id сломана. */
    int fd = open(path, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC, 0644);
    if (fd < 0) return nst_status_from_errno(errno);

    uint64_t now = nst_now_wall_ms();
    uint8_t hdr[NST_SEG_HDR_SIZE];
    encode_seg_header(hdr, file_id, now);

    nst_status st = nst_write_full(fd, hdr, sizeof hdr);
    if (st != NST_OK) {
        nst_close_fd(&fd);
        (void)unlink(path);
        return st;
    }

    *out = (nst_segment){ .file_id = file_id, .fd = fd, .created_ms = now,
                          .writable = true };
    atomic_store_explicit(&out->size, NST_SEG_HDR_SIZE, memory_order_release);
    return NST_OK;
}

nst_status nst_segment_open(const char *dir, uint32_t file_id, bool writable,
                            nst_segment *out) {
    char path[4096];
    seg_path(path, dir, file_id, "data");

    int fd = open(path, (writable ? O_RDWR : O_RDONLY) | O_CLOEXEC);
    if (fd < 0) return nst_status_from_errno(errno);

    nst_status st = NST_OK;
    uint8_t hdr[NST_SEG_HDR_SIZE];
    NST_TRY_GOTO(nst_pread_full(fd, hdr, sizeof hdr, 0), fail);

    if (memcmp(hdr, NST_SEG_MAGIC, sizeof NST_SEG_MAGIC) != 0) {
        st = NST_E_CORRUPT;
        goto fail;
    }
    if (nst_load_le32(hdr + 8) != NST_FORMAT_VERSION) {
        st = NST_E_UNSUPPORTED;
        goto fail;
    }
    if (nst_load_le64(hdr + 16) != file_id) {
        st = NST_E_CORRUPT;
        goto fail;
    }

    uint64_t size = 0;
    NST_TRY_GOTO(nst_file_size(fd, &size), fail);

    *out = (nst_segment){ .file_id = file_id, .fd = fd,
                          .created_ms = nst_load_le64(hdr + 24), .writable = writable };
    atomic_store_explicit(&out->size, size, memory_order_release);
    return NST_OK;

fail:
    nst_close_fd(&fd);
    return st;
}

void nst_segment_close(nst_segment *seg) {
    if (seg == nullptr) return;
    nst_close_fd(&seg->fd);
    atomic_store_explicit(&seg->size, 0, memory_order_release);
}

nst_status nst_segment_append(nst_segment *seg, const uint8_t *data, size_t len,
                              uint64_t *offset) {
    if (!seg->writable) return NST_E_INVAL;
    uint64_t off = atomic_load_explicit(&seg->size, memory_order_relaxed);
    /* pwrite вместо write: файловое смещение не участвует, значит
     * дозапись не ломается, если кто-то читает тот же дескриптор. */
    NST_TRY(nst_pwrite_full(seg->fd, data, len, (off_t)off));
    /* release-store: читатель, увидевший новый размер, увидит и байты. */
    atomic_store_explicit(&seg->size, off + len, memory_order_release);
    if (offset) *offset = off;
    return NST_OK;
}

nst_status nst_segment_read_record(const nst_segment *seg, uint64_t off, uint32_t len,
                                   uint8_t **buf, nst_record *rec) {
    if (len < NST_REC_HDR_SIZE || off + len > nst_segment_size(seg)) return NST_E_CORRUPT;

    uint8_t *tmp = malloc(len);
    if (tmp == nullptr) return NST_E_NOMEM;

    nst_status st = nst_pread_full(seg->fd, tmp, len, (off_t)off);
    if (st == NST_OK) st = nst_record_decode(tmp, len, rec, nullptr);
    if (st != NST_OK) { free(tmp); return st; }

    *buf = tmp;
    return NST_OK;
}

nst_status nst_segment_scan(nst_segment *seg, nst_segment_scan_fn fn, void *user,
                            uint64_t *valid_end) {
    constexpr size_t chunk = 1u << 20;
    uint8_t *buf = malloc(chunk);
    if (buf == nullptr) return NST_E_NOMEM;

    nst_status st = NST_OK;
    uint64_t off = NST_SEG_HDR_SIZE;
    uint64_t good = off;
    const uint64_t size = nst_segment_size(seg);

    while (off < size) {
        uint8_t hdr[NST_REC_HDR_SIZE];
        if (size - off < NST_REC_HDR_SIZE) break;   /* обрубленный заголовок */
        st = nst_pread_full(seg->fd, hdr, sizeof hdr, (off_t)off);
        if (st != NST_OK) break;

        uint32_t klen = 0, vlen = 0;
        if (nst_record_peek_header(hdr, &klen, &vlen, nullptr, nullptr) != NST_OK) break;

        size_t total;
        if (!nst_record_size(klen, vlen, &total)) break;
        if (off + total > size) break;                  /* обрубленное тело */

        uint8_t *rec_buf = buf;
        uint8_t *heap = nullptr;
        if (total > chunk) {
            heap = malloc(total);
            if (heap == nullptr) { st = NST_E_NOMEM; break; }
            rec_buf = heap;
        }

        st = nst_pread_full(seg->fd, rec_buf, total, (off_t)off);
        nst_record rec;
        if (st == NST_OK) st = nst_record_decode(rec_buf, total, &rec, nullptr);
        if (st != NST_OK) { free(heap); st = NST_OK; break; } /* битая запись — конец */

        bool go_on = fn(&rec, off, (uint32_t)total, user);
        free(heap);
        off += total;
        good = off;
        if (!go_on) break;
    }

    free(buf);
    if (valid_end) *valid_end = good;
    return st;
}

nst_status nst_segment_truncate(nst_segment *seg, uint64_t size) {
    if (ftruncate(seg->fd, (off_t)size) != 0) return nst_status_from_errno(errno);
    atomic_store_explicit(&seg->size, size, memory_order_release);
    NST_LOGW("segment %06" PRIu32 " truncated to %" PRIu64 " bytes", seg->file_id, size);
    return nst_fsync_fd(seg->fd);
}
