/* Hint-файл: компактный слепок индекса для одного сегмента.
 * Позволяет восстановить индекс при старте, не читая значения. */
#ifndef NESTOR_STORE_HINT_H
#define NESTOR_STORE_HINT_H

#include <stdint.h>

#include <nestor/status.h>
#include "store/index.h"
#include "util/buf.h"

/* Накопитель hint-записей; пишется одним атомарным файлом. */
typedef struct nst_hint_writer {
    nst_buf buf;
    uint32_t file_id;
    uint64_t entries;
} nst_hint_writer;

[[nodiscard]] nst_status nst_hint_writer_init(nst_hint_writer *w, uint32_t file_id);
void nst_hint_writer_free(nst_hint_writer *w);
[[nodiscard]] nst_status nst_hint_writer_add(nst_hint_writer *w, nst_slice key,
                                             uint64_t offset, uint32_t rec_len,
                                             uint64_t seq, uint8_t flags);
[[nodiscard]] nst_status nst_hint_writer_commit(nst_hint_writer *w, const char *dir);

/* Загрузить hint-файл сегмента в индекс. NST_E_NOTFOUND, если файла нет. */
typedef bool (*nst_hint_load_fn)(nst_slice key, uint64_t offset, uint32_t rec_len,
                                 uint64_t seq, uint8_t flags, void *user);
[[nodiscard]] nst_status nst_hint_load(const char *dir, uint32_t file_id,
                                       nst_hint_load_fn fn, void *user);

void nst_hint_remove(const char *dir, uint32_t file_id);

#endif /* NESTOR_STORE_HINT_H */
