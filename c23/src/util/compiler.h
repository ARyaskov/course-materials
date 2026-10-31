/* Атрибуты, встроенные функции и совместимость компиляторов. */
#ifndef NESTOR_UTIL_COMPILER_H
#define NESTOR_UTIL_COMPILER_H

#include <stddef.h>

#if !defined(__STDC_VERSION__) || __STDC_VERSION__ < 202311L
#  error "nestor требует компилятор в режиме C23 (-std=c23)"
#endif

/* Проверяем наличие атрибутов, а не версию компилятора. */
#if defined(__has_c_attribute)
#  if __has_c_attribute(gnu::always_inline)
#    define NST_ALWAYS_INLINE [[gnu::always_inline]] inline
#  endif
#  if __has_c_attribute(gnu::cleanup)
#    define NST_CLEANUP(fn) [[gnu::cleanup(fn)]]
#  endif
#  if __has_c_attribute(gnu::format)
#    define NST_PRINTF(fmt_idx, first_arg) [[gnu::format(printf, fmt_idx, first_arg)]]
#  endif
#  if __has_c_attribute(gnu::visibility)
#    define NST_API [[gnu::visibility("default")]]
#  endif
#endif

#ifndef NST_ALWAYS_INLINE
#  define NST_ALWAYS_INLINE inline
#endif
#ifndef NST_CLEANUP
#  define NST_CLEANUP(fn)
#endif
#ifndef NST_PRINTF
#  define NST_PRINTF(fmt_idx, first_arg)
#endif
#ifndef NST_API
#  define NST_API
#endif

#if defined(__has_builtin) && __has_builtin(__builtin_expect)
#  define NST_LIKELY(x)   __builtin_expect(!!(x), 1)
#  define NST_UNLIKELY(x) __builtin_expect(!!(x), 0)
#else
#  define NST_LIKELY(x)   (x)
#  define NST_UNLIKELY(x) (x)
#endif

#define NST_ARRAY_LEN(a) (sizeof(a) / sizeof((a)[0]))

/* Проверить статус и выйти из функции при ошибке. Одно вычисление expr. */
#define NST_TRY(expr)                                                         \
    do {                                                                      \
        nst_status nst_try_st_ = (expr);                                      \
        if (NST_UNLIKELY(nst_try_st_ != NST_OK)) return nst_try_st_;          \
    } while (0)

/* Перейти на метку очистки, сохранив статус в переменную st. */
#define NST_TRY_GOTO(expr, label)                                             \
    do {                                                                      \
        st = (expr);                                                          \
        if (NST_UNLIKELY(st != NST_OK)) goto label;                           \
    } while (0)

/* typeof + составной оператор: аргументы вычисляются один раз.
 * Составной оператор — расширение GNU, поэтому помечаем его __extension__,
 * чтобы -Wpedantic не ругался на каждое использование. */
#define NST_MIN(a, b) __extension__                                           \
    ({ typeof(a) nst_a_ = (a); typeof(b) nst_b_ = (b);                        \
       nst_a_ < nst_b_ ? nst_a_ : nst_b_; })
#define NST_MAX(a, b) __extension__                                           \
    ({ typeof(a) nst_a_ = (a); typeof(b) nst_b_ = (b);                        \
       nst_a_ > nst_b_ ? nst_a_ : nst_b_; })

#endif /* NESTOR_UTIL_COMPILER_H */
