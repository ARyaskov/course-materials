/* Функции C23, которых ещё нет в установленной libc.
 * Проверяем наличие, а не версию: как только glibc их экспортирует,
 * подставится стандартная реализация. */
#ifndef NESTOR_UTIL_COMPAT_H
#define NESTOR_UTIL_COMPAT_H

#include <stdlib.h>
#include <string.h>

#if defined(__GLIBC__) && defined(__GLIBC_PREREQ)
#  if __GLIBC_PREREQ(2, 43)
#    define NST_HAVE_C23_MEMSET_EXPLICIT 1
#    define NST_HAVE_C23_FREE_SIZED 1
#  endif
#endif

#if defined(NST_HAVE_C23_MEMSET_EXPLICIT)
static inline void *nst_memset_explicit(void *p, int c, size_t n) {
    return memset_explicit(p, c, n);
}
#else
/* volatile-указатель не даёт компилятору выбросить запись как мёртвую. */
static inline void *nst_memset_explicit(void *p, int c, size_t n) {
    volatile unsigned char *q = (volatile unsigned char *)p;
    while (n-- > 0) *q++ = (unsigned char)c;
    return p;
}
#endif

#if defined(NST_HAVE_C23_FREE_SIZED)
static inline void nst_free_sized(void *p, size_t size) { free_sized(p, size); }
#else
static inline void nst_free_sized(void *p, size_t size) { (void)size; free(p); }
#endif

#endif /* NESTOR_UTIL_COMPAT_H */
