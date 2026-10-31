/* Минимальный раннер тестов: регистрация через конструкторы,
 * один процесс, отчёт в конце. Внешних зависимостей нет. */
#ifndef NESTOR_TESTS_TEST_H
#define NESTOR_TESTS_TEST_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef void (*nst_test_fn)(void);

void nst_test_register(const char *name, nst_test_fn fn);
void nst_test_fail(const char *file, int line, const char *fmt, ...);

/* Конструктор регистрирует тест до входа в main. */
#define NST_TEST(name)                                                        \
    static void name(void);                                                   \
    [[gnu::constructor]] static void nst_reg_##name(void) {                   \
        nst_test_register(#name, name);                                       \
    }                                                                         \
    static void name(void)

#define NST_CHECK(cond)                                                       \
    do {                                                                      \
        if (!(cond)) nst_test_fail(__FILE__, __LINE__, "не выполнено: %s", #cond); \
    } while (0)

#define NST_CHECK_EQ(a, b)                                                    \
    do {                                                                      \
        long long nst_a_ = (long long)(a), nst_b_ = (long long)(b);           \
        if (nst_a_ != nst_b_)                                                 \
            nst_test_fail(__FILE__, __LINE__, "%s == %s: %lld != %lld",       \
                          #a, #b, nst_a_, nst_b_);                            \
    } while (0)

#define NST_CHECK_STATUS(expr, expected)                                      \
    do {                                                                      \
        nst_status nst_st_ = (expr);                                          \
        if (nst_st_ != (expected))                                            \
            nst_test_fail(__FILE__, __LINE__, "%s: ожидали %s, получили %s",  \
                          #expr, nst_status_str(expected), nst_status_str(nst_st_)); \
    } while (0)

#define NST_CHECK_MEM(a, b, n)                                                \
    do {                                                                      \
        if (memcmp((a), (b), (n)) != 0)                                       \
            nst_test_fail(__FILE__, __LINE__, "байты различаются: %s vs %s", #a, #b); \
    } while (0)

/* Временный каталог, удаляемый вызовом nst_test_rmdir_recursive. */
const char *nst_test_tmpdir(char buf[static 64]);
void nst_test_rmdir_recursive(const char *path);

#endif /* NESTOR_TESTS_TEST_H */
