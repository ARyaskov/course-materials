#define _GNU_SOURCE
#include "test.h"

#include <ftw.h>
#include <setjmp.h>
#include <stdarg.h>
#include <unistd.h>

typedef struct {
    const char *name;
    nst_test_fn fn;
} test_entry;

static test_entry g_tests[256];
static size_t g_count;
static jmp_buf g_jump;
static bool g_failed;

void nst_test_register(const char *name, nst_test_fn fn) {
    if (g_count == sizeof g_tests / sizeof g_tests[0]) {
        fprintf(stderr, "слишком много тестов\n");
        exit(2);
    }
    g_tests[g_count++] = (test_entry){ .name = name, .fn = fn };
}

void nst_test_fail(const char *file, int line, const char *fmt, ...) {
    const char *slash = strrchr(file, '/');
    fprintf(stderr, "    %s:%d ", slash ? slash + 1 : file, line);
    va_list ap;
    va_start(ap);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    g_failed = true;
    longjmp(g_jump, 1);
}

const char *nst_test_tmpdir(char buf[static 64]) {
    snprintf(buf, 64, "/tmp/nestor-test-%d-%ld", (int)getpid(), random());
    return buf;
}

static int unlink_cb(const char *path, const struct stat *sb, int type, struct FTW *ftw) {
    (void)sb; (void)type; (void)ftw;
    return remove(path);
}

void nst_test_rmdir_recursive(const char *path) {
    (void)nftw(path, unlink_cb, 16, FTW_DEPTH | FTW_PHYS);
}

static int cmp_entry(const void *a, const void *b) {
    return strcmp(((const test_entry *)a)->name, ((const test_entry *)b)->name);
}

int main(int argc, char **argv) {
    /* volatile: переменная переживает longjmp из проваленного теста. */
    const char *volatile filter = argc > 1 ? argv[1] : nullptr;
    qsort(g_tests, g_count, sizeof g_tests[0], cmp_entry);

    size_t run = 0, failed = 0;
    for (size_t i = 0; i < g_count; i++) {
        if (filter != nullptr && strstr(g_tests[i].name, filter) == nullptr) continue;
        run++;
        g_failed = false;
        printf("[ RUN  ] %s\n", g_tests[i].name);
        fflush(stdout);
        if (setjmp(g_jump) == 0) g_tests[i].fn();
        if (g_failed) { failed++; printf("[ FAIL ] %s\n", g_tests[i].name); }
        else printf("[  OK  ] %s\n", g_tests[i].name);
    }

    printf("\n%zu тестов, %zu провалов\n", run, failed);
    return failed == 0 ? 0 : 1;
}
