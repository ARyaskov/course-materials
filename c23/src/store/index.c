#include "store/index.h"

#include <stdbit.h>
#include <stdckdint.h>
#include <stdlib.h>
#include <string.h>

#include "util/compiler.h"
#include "util/hash.h"

/* Два зарезервированных значения хеша вместо отдельного массива состояний:
 * экономит одно обращение к памяти на пробу. */
constexpr uint64_t SLOT_EMPTY = 0;
constexpr uint64_t SLOT_TOMB  = 1;

static uint64_t key_hash(nst_slice key) {
    uint64_t h = nst_hash_key(key.ptr, key.len);
    return (h <= SLOT_TOMB) ? SLOT_TOMB + 1 : h;
}

nst_status nst_index_init(nst_index *ix, size_t initial_cap) {
    size_t cap = initial_cap < 16 ? 16 : initial_cap;
    cap = stdc_bit_ceil((unsigned long long)cap); /* до степени двойки вверх */
    nst_index_entry *slots = calloc(cap, sizeof *slots);
    if (slots == nullptr) return NST_E_NOMEM;
    *ix = (nst_index){ .slots = slots, .cap = cap };
    return NST_OK;
}

void nst_index_destroy(nst_index *ix) {
    if (ix->slots != nullptr) {
        for (size_t i = 0; i < ix->cap; i++)
            if (ix->slots[i].hash > SLOT_TOMB) free(ix->slots[i].key);
        free(ix->slots);
    }
    *ix = (nst_index){};
}

static bool slot_matches(const nst_index_entry *e, uint64_t h, nst_slice key) {
    return e->hash == h && e->key_len == key.len &&
           memcmp(e->key, key.ptr, key.len) == 0;
}

/* Найти слот ключа (found=true) или первый пригодный для вставки. */
static size_t probe(const nst_index *ix, uint64_t h, nst_slice key, bool *found) {
    size_t mask = ix->cap - 1;
    size_t i = (size_t)h & mask;
    size_t first_tomb = SIZE_MAX;
    for (;;) {
        nst_index_entry *e = &ix->slots[i];
        if (e->hash == SLOT_EMPTY) {
            *found = false;
            return first_tomb != SIZE_MAX ? first_tomb : i;
        }
        if (e->hash == SLOT_TOMB) {
            if (first_tomb == SIZE_MAX) first_tomb = i;
        } else if (slot_matches(e, h, key)) {
            *found = true;
            return i;
        }
        i = (i + 1) & mask;
    }
}

static nst_status index_grow(nst_index *ix) {
    size_t new_cap;
    if (ckd_mul(&new_cap, ix->cap, (size_t)2)) return NST_E_NOMEM;
    nst_index_entry *slots = calloc(new_cap, sizeof *slots);
    if (slots == nullptr) return NST_E_NOMEM;

    nst_index old = *ix;
    ix->slots = slots;
    ix->cap = new_cap;
    ix->used = ix->count = 0;
    ix->key_bytes = 0;

    size_t mask = new_cap - 1;
    for (size_t i = 0; i < old.cap; i++) {
        nst_index_entry *e = &old.slots[i];
        if (e->hash <= SLOT_TOMB) continue;
        size_t j = (size_t)e->hash & mask;
        while (ix->slots[j].hash != SLOT_EMPTY) j = (j + 1) & mask;
        ix->slots[j] = *e;   /* владение ключом переезжает как есть */
        ix->used++;
        ix->count++;
        ix->key_bytes += e->key_len;
    }
    free(old.slots);
    return NST_OK;
}

nst_status nst_index_put(nst_index *ix, nst_slice key, nst_loc loc, bool *stored,
                         nst_loc *replaced) {
    if (key.len == 0) return NST_E_INVAL;
    /* Коэффициент заполнения 0.7: дальше линейное пробирование деградирует. */
    if ((ix->used + 1) * 10 >= ix->cap * 7) NST_TRY(index_grow(ix));

    uint64_t h = key_hash(key);
    bool found = false;
    size_t i = probe(ix, h, key, &found);
    nst_index_entry *e = &ix->slots[i];

    if (found) {
        if (loc.seq < e->loc.seq) {          /* пришла более старая версия */
            if (stored) *stored = false;
            if (replaced) *replaced = loc;
            return NST_OK;
        }
        if (replaced) *replaced = e->loc;
        e->loc = loc;
        if (stored) *stored = true;
        return NST_OK;
    }

    uint8_t *copy = malloc(key.len);
    if (copy == nullptr) return NST_E_NOMEM;
    memcpy(copy, key.ptr, key.len);

    if (e->hash == SLOT_EMPTY) ix->used++;   /* переиспользование tomb не растит used */
    *e = (nst_index_entry){ .hash = h, .key = copy,
                            .key_len = (uint32_t)key.len, .loc = loc };
    ix->count++;
    ix->key_bytes += key.len;
    if (stored) *stored = true;
    if (replaced) *replaced = (nst_loc){};
    return NST_OK;
}

bool nst_index_get(const nst_index *ix, nst_slice key, nst_loc *out) {
    if (key.len == 0 || ix->count == 0) return false;
    uint64_t h = key_hash(key);
    bool found = false;
    size_t i = probe(ix, h, key, &found);
    if (!found) return false;
    if (out) *out = ix->slots[i].loc;
    return true;
}

bool nst_index_remove(nst_index *ix, nst_slice key, nst_loc *removed) {
    if (key.len == 0 || ix->count == 0) return false;
    uint64_t h = key_hash(key);
    bool found = false;
    size_t i = probe(ix, h, key, &found);
    if (!found) return false;

    nst_index_entry *e = &ix->slots[i];
    if (removed) *removed = e->loc;
    free(e->key);
    ix->key_bytes -= e->key_len;
    *e = (nst_index_entry){ .hash = SLOT_TOMB };
    ix->count--;
    return true;
}

void nst_index_foreach(const nst_index *ix, nst_index_iter_fn fn, void *user) {
    for (size_t i = 0; i < ix->cap; i++) {
        const nst_index_entry *e = &ix->slots[i];
        if (e->hash <= SLOT_TOMB) continue;
        nst_slice key = { .ptr = e->key, .len = e->key_len };
        if (!fn(key, e->loc, user)) return;
    }
}
