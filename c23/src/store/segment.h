/* Сегмент данных: файл вида 000042.data с заголовком и потоком записей.
 * Активный сегмент открыт на дозапись, остальные — только на чтение. */
#ifndef NESTOR_STORE_SEGMENT_H
#define NESTOR_STORE_SEGMENT_H

#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>

#include <nestor/status.h>
#include "store/record.h"
#include "util/slice.h"

typedef struct nst_segment {
    uint32_t file_id;
    int fd;
    /* Длина файла растёт в потоке-писателе и читается читателями под
     * другой блокировкой, поэтому поле атомарное: обычный uint64_t здесь —
     * гонка данных, которую ловит ThreadSanitizer. */
    _Atomic uint64_t size;
    uint64_t live_bytes;   /* байт, на которые ещё ссылается индекс */
    uint64_t created_ms;
    bool writable;
} nst_segment;

/* Имя файла сегмента/hint: "000042.data" / "000042.hint". */
void nst_segment_name(char buf[static 32], uint32_t file_id, const char *ext);

/* Создать новый файл сегмента с заголовком. */
[[nodiscard]] nst_status nst_segment_create(const char *dir, uint32_t file_id,
                                            nst_segment *out);
/* Открыть существующий: проверить магию и версию формата. */
[[nodiscard]] nst_status nst_segment_open(const char *dir, uint32_t file_id,
                                          bool writable, nst_segment *out);
void nst_segment_close(nst_segment *seg);

static inline uint64_t nst_segment_size(const nst_segment *seg) {
    return atomic_load_explicit(&seg->size, memory_order_acquire);
}

/* Дозаписать закодированную запись; *offset получает её смещение. */
[[nodiscard]] nst_status nst_segment_append(nst_segment *seg, const uint8_t *data,
                                            size_t len, uint64_t *offset);

/* Прочитать запись по смещению и длине из индекса. Буфер выделяется
 * функцией; освобождать через free. */
[[nodiscard]] nst_status nst_segment_read_record(const nst_segment *seg, uint64_t off,
                                                 uint32_t len, uint8_t **buf,
                                                 nst_record *rec);

/* Последовательный обход файла при восстановлении.
 * Колбэк возвращает false, чтобы прервать обход. */
typedef bool (*nst_segment_scan_fn)(const nst_record *rec, uint64_t offset,
                                    uint32_t rec_len, void *user);
/* При повреждённом хвосте возвращает NST_OK и выставляет *valid_end
 * в конец последней целой записи — этот хвост нужно усечь. */
[[nodiscard]] nst_status nst_segment_scan(nst_segment *seg, nst_segment_scan_fn fn,
                                          void *user, uint64_t *valid_end);

/* Усечь файл до заданной длины (после обнаружения битого хвоста). */
[[nodiscard]] nst_status nst_segment_truncate(nst_segment *seg, uint64_t size);

#endif /* NESTOR_STORE_SEGMENT_H */
