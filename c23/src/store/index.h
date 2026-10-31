/* Хеш-индекс в памяти: ключ -> расположение последней записи на диске.
 * Открытая адресация с линейным пробированием, ёмкость — степень двойки.
 * Ключи копируются в индекс, значения на диске. */
#ifndef NESTOR_STORE_INDEX_H
#define NESTOR_STORE_INDEX_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <nestor/status.h>
#include "util/slice.h"

typedef struct nst_loc {
    uint64_t offset;    /* смещение записи в файле сегмента */
    uint64_t seq;       /* номер версии: больше — новее */
    uint32_t file_id;
    uint32_t rec_len;   /* полная длина записи на диске */
} nst_loc;

typedef struct nst_index_entry {
    uint64_t hash;      /* 0 — пусто, 1 — удалённый слот (см. index.c) */
    uint8_t *key;
    uint32_t key_len;
    nst_loc loc;
} nst_index_entry;

typedef struct nst_index {
    nst_index_entry *slots;
    size_t cap;         /* всегда степень двойки */
    size_t used;        /* занятых слотов, включая удалённые */
    size_t count;       /* живых ключей */
    uint64_t key_bytes; /* сколько памяти занято копиями ключей */
} nst_index;

[[nodiscard]] nst_status nst_index_init(nst_index *ix, size_t initial_cap);
void nst_index_destroy(nst_index *ix);

/* Вставить или обновить. Обновление происходит, только если loc.seq больше
 * текущего: так восстановление из нескольких сегментов не зависит от порядка.
 * *replaced (если не nullptr) получает вытесненное расположение. */
[[nodiscard]] nst_status nst_index_put(nst_index *ix, nst_slice key, nst_loc loc,
                                       bool *stored, nst_loc *replaced);

bool nst_index_get(const nst_index *ix, nst_slice key, nst_loc *out);

/* Удалить ключ. Возвращает false, если ключа не было. */
bool nst_index_remove(nst_index *ix, nst_slice key, nst_loc *removed);

typedef bool (*nst_index_iter_fn)(nst_slice key, nst_loc loc, void *user);
void nst_index_foreach(const nst_index *ix, nst_index_iter_fn fn, void *user);

static inline size_t nst_index_count(const nst_index *ix) { return ix->count; }

#endif /* NESTOR_STORE_INDEX_H */
