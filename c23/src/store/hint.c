#define _GNU_SOURCE
#include "store/hint.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "store/format.h"
#include "store/segment.h"
#include "util/compiler.h"
#include "util/endian.h"
#include "util/io.h"

nst_status nst_hint_writer_init(nst_hint_writer *w, uint32_t file_id) {
    *w = (nst_hint_writer){ .file_id = file_id };
    nst_buf_init(&w->buf);

    uint8_t hdr[NST_SEG_HDR_SIZE];
    memset(hdr, 0, sizeof hdr);
    memcpy(hdr, NST_HINT_MAGIC, sizeof NST_HINT_MAGIC);
    nst_store_le32(hdr + 8, NST_FORMAT_VERSION);
    nst_store_le64(hdr + 16, file_id);
    return nst_buf_append(&w->buf, hdr, sizeof hdr);
}

void nst_hint_writer_free(nst_hint_writer *w) { nst_buf_free(&w->buf); }

nst_status nst_hint_writer_add(nst_hint_writer *w, nst_slice key, uint64_t offset,
                               uint32_t rec_len, uint64_t seq, uint8_t flags) {
    if (key.len == 0 || key.len > NST_MAX_KEY_BYTES) return NST_E_INVAL;

    uint8_t ent[NST_HINT_ENT_SIZE];
    nst_store_le64(ent, offset);
    nst_store_le32(ent + 8, rec_len);
    nst_store_le64(ent + 12, seq);
    nst_store_le16(ent + 20, (uint16_t)key.len);
    ent[22] = flags;
    ent[23] = 0;

    NST_TRY(nst_buf_append(&w->buf, ent, sizeof ent));
    NST_TRY(nst_buf_append_slice(&w->buf, key));
    w->entries++;
    return NST_OK;
}

nst_status nst_hint_writer_commit(nst_hint_writer *w, const char *dir) {
    char name[32];
    nst_segment_name(name, w->file_id, "hint");
    return nst_write_file_atomic(dir, name, w->buf.data, w->buf.len);
}

nst_status nst_hint_load(const char *dir, uint32_t file_id, nst_hint_load_fn fn,
                         void *user) {
    char name[32], path[4096];
    nst_segment_name(name, file_id, "hint");
    snprintf(path, sizeof path, "%s/%s", dir, name);

    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return errno == ENOENT ? NST_E_NOTFOUND : nst_status_from_errno(errno);

    nst_status st = NST_OK;
    uint8_t *data = nullptr;
    uint64_t size = 0;
    NST_TRY_GOTO(nst_file_size(fd, &size), done);
    if (size < NST_SEG_HDR_SIZE) { st = NST_E_CORRUPT; goto done; }

    data = malloc((size_t)size);
    if (data == nullptr) { st = NST_E_NOMEM; goto done; }
    NST_TRY_GOTO(nst_pread_full(fd, data, (size_t)size, 0), done);

    if (memcmp(data, NST_HINT_MAGIC, sizeof NST_HINT_MAGIC) != 0 ||
        nst_load_le32(data + 8) != NST_FORMAT_VERSION ||
        nst_load_le64(data + 16) != file_id) {
        st = NST_E_CORRUPT;
        goto done;
    }

    for (size_t off = NST_SEG_HDR_SIZE; off < size; ) {
        if (size - off < NST_HINT_ENT_SIZE) { st = NST_E_CORRUPT; goto done; }
        const uint8_t *ent = data + off;
        uint64_t rec_off = nst_load_le64(ent);
        uint32_t rec_len = nst_load_le32(ent + 8);
        uint64_t seq = nst_load_le64(ent + 12);
        uint32_t key_len = nst_load_le16(ent + 20);
        uint8_t flags = ent[22];

        off += NST_HINT_ENT_SIZE;
        if (key_len == 0 || size - off < key_len) { st = NST_E_CORRUPT; goto done; }

        nst_slice key = { .ptr = data + off, .len = key_len };
        off += key_len;
        if (!fn(key, rec_off, rec_len, seq, flags, user)) break;
    }

done:
    free(data);
    nst_close_fd(&fd);
    return st;
}

void nst_hint_remove(const char *dir, uint32_t file_id) {
    char name[32], path[4096];
    nst_segment_name(name, file_id, "hint");
    snprintf(path, sizeof path, "%s/%s", dir, name);
    (void)unlink(path);
}
