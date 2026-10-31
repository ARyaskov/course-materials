/* Слайс — указатель и длина. Основной «строковый» тип проекта:
 * ключи и значения хранилища бинарно безопасны и не заканчиваются нулём. */
#ifndef NESTOR_UTIL_SLICE_H
#define NESTOR_UTIL_SLICE_H

#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#include <nestor/nestor.h>

#define NST_SLICE_LIT(s) ((nst_slice){ .ptr = (const uint8_t *)("" s), .len = sizeof(s) - 1 })

static inline bool nst_slice_empty(nst_slice s) { return s.len == 0; }

static inline bool nst_slice_eq(nst_slice a, nst_slice b) {
    return a.len == b.len && (a.len == 0 || memcmp(a.ptr, b.ptr, a.len) == 0);
}

/* Лексикографическое сравнение по байтам, как memcmp. */
int nst_slice_cmp(nst_slice a, nst_slice b);

/* Подслайс [off, off + len). Выход за границы усекается. */
nst_slice nst_slice_sub(nst_slice s, size_t off, size_t len);

/* Первое вхождение байта; SIZE_MAX, если байта нет. */
size_t nst_slice_find_byte(nst_slice s, uint8_t byte);

bool nst_slice_starts_with(nst_slice s, nst_slice prefix);

/* Разрезать по первому вхождению byte. Возвращает false, если байта нет;
 * при этом *head и *tail не изменяются. */
bool nst_slice_split_byte(nst_slice s, uint8_t byte, nst_slice *head, nst_slice *tail);

/* Копия в свежий буфер malloc; освобождать через nst_free_value. */
[[nodiscard]] nst_status nst_slice_dup(nst_slice s, nst_slice *out);

/* Скопировать как C-строку в буфер размера cap (с завершающим нулём).
 * false, если не помещается или внутри есть нулевой байт. */
bool nst_slice_to_cstr(nst_slice s, char *buf, size_t cap);

#endif /* NESTOR_UTIL_SLICE_H */
