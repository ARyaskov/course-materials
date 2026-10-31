/* Тонкая обёртка над POSIX I/O: полные чтения и записи, обработка EINTR,
 * атомарная замена файла, fsync каталога. */
#ifndef NESTOR_UTIL_IO_H
#define NESTOR_UTIL_IO_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

#include <nestor/status.h>

/* Записать n байт целиком: цикл вокруг write, повтор при EINTR. */
[[nodiscard]] nst_status nst_write_full(int fd, const void *buf, size_t n);
/* Прочитать n байт целиком с позиции off. NST_E_CORRUPT при коротком чтении. */
[[nodiscard]] nst_status nst_pread_full(int fd, void *buf, size_t n, off_t off);
/* Дозаписать n байт по позиции off (без изменения файлового смещения). */
[[nodiscard]] nst_status nst_pwrite_full(int fd, const void *buf, size_t n, off_t off);

[[nodiscard]] nst_status nst_fsync_fd(int fd);
/* fsync каталога: без него rename/creat могут не пережить отключение питания. */
[[nodiscard]] nst_status nst_fsync_dir(const char *dir);

/* Атомарная замена: пишем во временный файл, fsync, rename, fsync каталога. */
[[nodiscard]] nst_status nst_write_file_atomic(const char *dir, const char *name,
                                               const void *data, size_t len);

[[nodiscard]] nst_status nst_file_size(int fd, uint64_t *out);

/* Закрыть дескриптор, игнорируя EINTR; обнуляет *fd в -1. */
void nst_close_fd(int *fd);

/* Для [[gnu::cleanup]]: void f(int *fd). */
static inline void nst_fd_cleanup(int *fd) { nst_close_fd(fd); }

#endif /* NESTOR_UTIL_IO_H */
