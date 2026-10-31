/* Однопоточный событийный сервер поверх epoll.
 * Все операции с базой выполняются в потоке цикла; libnestor
 * потокобезопасен, так что при необходимости циклов может быть несколько. */
#ifndef NESTOR_NET_SERVER_H
#define NESTOR_NET_SERVER_H

#include <stdbool.h>
#include <stdint.h>

#include <nestor/nestor.h>
#include <nestor/status.h>

typedef struct nst_server_config {
    const char *host;          /* nullptr -> "0.0.0.0" */
    uint16_t port;             /* 0 -> 7717 */
    const char *unix_path;     /* если задан, слушаем ещё и unix-сокет */
    uint32_t max_connections;  /* 0 -> 1024 */
    uint32_t max_out_buffer;   /* 0 -> 8 МиБ, защита от медленных клиентов */
    uint32_t idle_timeout_ms;  /* 0 -> без таймаута */
} nst_server_config;

typedef struct nst_server nst_server;

/* Заблокировать SIGINT/SIGTERM в текущем потоке.
 * Вызывать в main ДО создания любых потоков (включая nst_open с фоновой
 * компакцией): маска наследуется при pthread_create, а сигнал процесса
 * получает любой поток, который его не блокирует. Иначе SIGTERM убьёт
 * процесс через фоновый поток, не дойдя до signalfd. */
[[nodiscard]] nst_status nst_server_block_signals(void);

[[nodiscard]] nst_status nst_server_create(nst_db *db, const nst_server_config *cfg,
                                           nst_server **out);
/* Цикл выполняется до получения SIGINT/SIGTERM через signalfd. */
[[nodiscard]] nst_status nst_server_run(nst_server *srv);
void nst_server_destroy(nst_server *srv);

/* Фактический порт (полезно, когда в конфиге указан 0 для автовыбора). */
uint16_t nst_server_port(const nst_server *srv);

#endif /* NESTOR_NET_SERVER_H */
