#define _GNU_SOURCE
#include "util/io.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "util/compiler.h"
#include "util/log.h"

nst_status nst_write_full(int fd, const void *buf, size_t n) {
    const unsigned char *p = buf;
    while (n > 0) {
        ssize_t w = write(fd, p, n);
        if (w < 0) {
            if (errno == EINTR) continue;   /* сигнал прервал вызов — повторяем */
            return nst_status_from_errno(errno);
        }
        /* write может записать меньше запрошенного даже на обычном файле. */
        p += (size_t)w;
        n -= (size_t)w;
    }
    return NST_OK;
}

nst_status nst_pread_full(int fd, void *buf, size_t n, off_t off) {
    unsigned char *p = buf;
    while (n > 0) {
        ssize_t r = pread(fd, p, n, off);
        if (r < 0) {
            if (errno == EINTR) continue;
            return nst_status_from_errno(errno);
        }
        if (r == 0) return NST_E_CORRUPT;   /* файл короче, чем говорит индекс */
        p += (size_t)r;
        n -= (size_t)r;
        off += r;
    }
    return NST_OK;
}

nst_status nst_pwrite_full(int fd, const void *buf, size_t n, off_t off) {
    const unsigned char *p = buf;
    while (n > 0) {
        ssize_t w = pwrite(fd, p, n, off);
        if (w < 0) {
            if (errno == EINTR) continue;
            return nst_status_from_errno(errno);
        }
        p += (size_t)w;
        n -= (size_t)w;
        off += w;
    }
    return NST_OK;
}

nst_status nst_fsync_fd(int fd) {
    while (fsync(fd) != 0) {
        if (errno == EINTR) continue;
        return nst_status_from_errno(errno);
    }
    return NST_OK;
}

nst_status nst_fsync_dir(const char *dir) {
    int fd = open(dir, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (fd < 0) return nst_status_from_errno(errno);
    nst_status st = nst_fsync_fd(fd);
    nst_close_fd(&fd);
    return st;
}

nst_status nst_file_size(int fd, uint64_t *out) {
    struct stat sb;
    if (fstat(fd, &sb) != 0) return nst_status_from_errno(errno);
    *out = (uint64_t)sb.st_size;
    return NST_OK;
}

void nst_close_fd(int *fd) {
    if (fd == nullptr || *fd < 0) return;
    /* close() нельзя повторять при EINTR: на Linux дескриптор уже закрыт. */
    (void)close(*fd);
    *fd = -1;
}

nst_status nst_write_file_atomic(const char *dir, const char *name,
                                 const void *data, size_t len) {
    char tmp_path[4096];
    char final_path[4096];
    if (snprintf(tmp_path, sizeof tmp_path, "%s/%s.tmp", dir, name) >= (int)sizeof tmp_path)
        return NST_E_INVAL;
    if (snprintf(final_path, sizeof final_path, "%s/%s", dir, name) >= (int)sizeof final_path)
        return NST_E_INVAL;

    int fd = open(tmp_path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
    if (fd < 0) return nst_status_from_errno(errno);

    nst_status st = nst_write_full(fd, data, len);
    if (st == NST_OK) st = nst_fsync_fd(fd);
    nst_close_fd(&fd);
    if (st != NST_OK) { (void)unlink(tmp_path); return st; }

    if (rename(tmp_path, final_path) != 0) {
        st = nst_status_from_errno(errno);
        (void)unlink(tmp_path);
        return st;
    }
    /* Имя появляется в каталоге только после fsync каталога. */
    return nst_fsync_dir(dir);
}
