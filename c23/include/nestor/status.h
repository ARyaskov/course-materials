/* nestor — коды состояния публичного API. */
#ifndef NESTOR_STATUS_H
#define NESTOR_STATUS_H

#include <stdint.h>

/* Единый список кодов. Из него генерируются enum и таблица строк
 * (X-макрос, глава 7). Добавлять новые коды только в конец. */
#define NST_STATUS_LIST(X)                                                    \
    X(NST_OK,              0, "ok")                                           \
    X(NST_E_INVAL,         1, "invalid argument")                             \
    X(NST_E_NOMEM,         2, "out of memory")                                \
    X(NST_E_IO,            3, "io error")                                     \
    X(NST_E_NOTFOUND,      4, "key not found")                                \
    X(NST_E_CORRUPT,       5, "corrupted data")                               \
    X(NST_E_LOCKED,        6, "directory is locked by another process")       \
    X(NST_E_TOOBIG,        7, "key or value is too large")                    \
    X(NST_E_FULL,          8, "storage limit reached")                        \
    X(NST_E_CLOSED,        9, "database is closed")                           \
    X(NST_E_UNSUPPORTED,  10, "unsupported format version")                   \
    X(NST_E_AGAIN,        11, "operation would block")                        \
    X(NST_E_PROTO,        12, "protocol error")

enum nst_status : int32_t {
#define NST_X(name, value, text) name = (value),
    NST_STATUS_LIST(NST_X)
#undef NST_X
};

typedef enum nst_status nst_status;

/* Человекочитаемое описание кода. Никогда не возвращает nullptr. */
const char *nst_status_str(nst_status st);

/* Отображение errno в код nestor. Вызывать сразу после неудачного
 * системного вызова, пока errno не затёрт. */
nst_status nst_status_from_errno(int err);

#endif /* NESTOR_STATUS_H */
