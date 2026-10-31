#include "util/slice.h"

#include <stdint.h>
#include <stdlib.h>

#include "util/compiler.h"

nst_slice nst_slice_str(const char *s) {
    if (s == nullptr) return (nst_slice){};
    return (nst_slice){ .ptr = (const uint8_t *)s, .len = strlen(s) };
}

int nst_slice_cmp(nst_slice a, nst_slice b) {
    size_t n = NST_MIN(a.len, b.len);
    int r = (n == 0) ? 0 : memcmp(a.ptr, b.ptr, n);
    if (r != 0) return r;
    if (a.len == b.len) return 0;
    return a.len < b.len ? -1 : 1;
}

nst_slice nst_slice_sub(nst_slice s, size_t off, size_t len) {
    if (off >= s.len) return (nst_slice){ .ptr = s.ptr, .len = 0 };
    size_t avail = s.len - off;
    return (nst_slice){ .ptr = s.ptr + off, .len = len < avail ? len : avail };
}

size_t nst_slice_find_byte(nst_slice s, uint8_t byte) {
    if (s.len == 0) return SIZE_MAX;
    const uint8_t *p = memchr(s.ptr, byte, s.len);
    return p == nullptr ? SIZE_MAX : (size_t)(p - s.ptr);
}

bool nst_slice_starts_with(nst_slice s, nst_slice prefix) {
    if (prefix.len > s.len) return false;
    return prefix.len == 0 || memcmp(s.ptr, prefix.ptr, prefix.len) == 0;
}

bool nst_slice_split_byte(nst_slice s, uint8_t byte, nst_slice *head, nst_slice *tail) {
    size_t pos = nst_slice_find_byte(s, byte);
    if (pos == SIZE_MAX) return false;
    *head = nst_slice_sub(s, 0, pos);
    *tail = nst_slice_sub(s, pos + 1, s.len - pos - 1);
    return true;
}

nst_status nst_slice_dup(nst_slice s, nst_slice *out) {
    if (out == nullptr) return NST_E_INVAL;
    /* Для пустого слайса всё равно выделяем байт: указатель должен быть
     * уникальным и пригодным для free. */
    uint8_t *buf = malloc(s.len + 1);
    if (buf == nullptr) return NST_E_NOMEM;
    if (s.len > 0) memcpy(buf, s.ptr, s.len);
    buf[s.len] = 0;
    *out = (nst_slice){ .ptr = buf, .len = s.len };
    return NST_OK;
}

void nst_free_value(nst_slice value) {
    /* Слайс отдаёт const-указатель, но владельцем буфера остаётся
     * вызывающая сторона. Снимаем const через uintptr_t: прямой каст
     * ловится -Wcast-qual, а этот путь стандартом разрешён. */
    free((void *)(uintptr_t)value.ptr);
}

bool nst_slice_to_cstr(nst_slice s, char *buf, size_t cap) {
    if (cap == 0 || s.len + 1 > cap) return false;
    if (nst_slice_find_byte(s, 0) != SIZE_MAX) return false;
    if (s.len > 0) memcpy(buf, s.ptr, s.len);
    buf[s.len] = '\0';
    return true;
}
