/* nestor — встраиваемое log-structured key-value хранилище.
 *
 * Модель: append-only сегменты на диске + hash-индекс в памяти.
 * Чтение по ключу — одно позиционное чтение с диска (pread) или
 * обращение к отображённой странице. Запись — дозапись в активный
 * сегмент. Удаление — запись-надгробие (tombstone). Место освобождает
 * фоновая компакция.
 *
 * Потокобезопасность: nst_db безопасен для одновременного использования
 * из нескольких потоков. Записи сериализуются внутренним мьютексом,
 * чтения выполняются параллельно.
 */
#ifndef NESTOR_NESTOR_H
#define NESTOR_NESTOR_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <nestor/status.h>

#define NST_VERSION_MAJOR 1
#define NST_VERSION_MINOR 0
#define NST_VERSION_PATCH 0

/* Строка версии вида "1.0.0". */
const char *nst_version(void);

/* Непрозрачный дескриптор базы: определение скрыто в src/store/db.c. */
typedef struct nst_db nst_db;

/* Ссылка на непрерывный участок байтов. Не владеет памятью.
 * Ключи и значения — произвольные байты, нулевой байт допустим. */
typedef struct nst_slice {
    const uint8_t *ptr;
    size_t len;
} nst_slice;

/* Политика долговечности записи. */
typedef enum nst_sync_mode : uint8_t {
    NST_SYNC_NEVER = 0,    /* полагаемся на страничный кэш ядра */
    NST_SYNC_INTERVAL = 1, /* fsync не чаще, чем раз в sync_interval_ms */
    NST_SYNC_ALWAYS = 2,   /* fsync после каждой записи */
} nst_sync_mode;

typedef struct nst_options {
    uint64_t max_segment_bytes;  /* ротация активного сегмента; 0 -> 256 МиБ */
    uint32_t max_key_bytes;      /* 0 -> 65535 */
    uint32_t max_value_bytes;    /* 0 -> 16 МиБ */
    nst_sync_mode sync_mode;
    uint32_t sync_interval_ms;   /* для NST_SYNC_INTERVAL; 0 -> 1000 */
    bool read_only;              /* открыть без блокировки на запись */
    bool background_compaction;  /* запустить поток компакции */
    double compaction_garbage_ratio; /* 0 -> 0.4 */
    uint32_t compaction_interval_ms; /* 0 -> 30000 */
} nst_options;

/* Значения по умолчанию: nst_options o = nst_options_default(); */
nst_options nst_options_default(void);

/* Счётчики, которые отдаёт команда STATS сервера. */
typedef struct nst_stats {
    uint64_t keys;            /* живых ключей в индексе */
    uint64_t segments;        /* открытых сегментов данных */
    uint64_t live_bytes;      /* байт, на которые ссылается индекс */
    uint64_t total_bytes;     /* байт на диске во всех сегментах */
    uint64_t puts;
    uint64_t gets;
    uint64_t deletes;
    uint64_t get_misses;
    uint64_t compactions;
    uint64_t reclaimed_bytes;
    uint64_t fsyncs;
} nst_stats;

/* Открыть или создать базу в каталоге dir.
 * opts может быть nullptr — тогда берутся значения по умолчанию.
 * При успехе *out получает владение базой; закрывать через nst_close. */
[[nodiscard]] nst_status nst_open(const char *dir, const nst_options *opts, nst_db **out);

/* Закрыть базу: остановить компактор, сбросить буферы, снять блокировку.
 * nullptr допустим и ничего не делает. */
void nst_close(nst_db *db);

/* Записать значение. Ключ и значение копируются, вызывающая сторона
 * может освободить их сразу после возврата. */
[[nodiscard]] nst_status nst_put(nst_db *db, nst_slice key, nst_slice value);

/* Прочитать значение. При NST_OK *out указывает на буфер, выделенный
 * функцией; освобождать через nst_free_value. При NST_E_NOTFOUND
 * *out не изменяется. */
[[nodiscard]] nst_status nst_get(nst_db *db, nst_slice key, nst_slice *out);

/* Освободить значение, полученное из nst_get. */
void nst_free_value(nst_slice value);

/* Удалить ключ. Отсутствие ключа — NST_E_NOTFOUND, а не ошибка записи. */
[[nodiscard]] nst_status nst_delete(nst_db *db, nst_slice key);

/* Есть ли ключ в индексе, без чтения значения с диска. */
bool nst_contains(nst_db *db, nst_slice key);

/* Обход всех живых ключей. Колбэк получает ключ, действительный только
 * на время вызова, и user. Возврат false останавливает обход. */
typedef bool (*nst_scan_fn)(nst_slice key, void *user);
[[nodiscard]] nst_status nst_scan(nst_db *db, nst_scan_fn fn, void *user);

/* Принудительный fsync активного сегмента. */
[[nodiscard]] nst_status nst_sync(nst_db *db);

/* Синхронная компакция: слить сегменты, у которых доля мусора выше
 * порога, и удалить старые файлы. */
[[nodiscard]] nst_status nst_compact(nst_db *db);

void nst_get_stats(nst_db *db, nst_stats *out);

/* Вспомогательные конструкторы слайсов. */
static inline nst_slice nst_slice_bytes(const void *p, size_t n) {
    return (nst_slice){ .ptr = (const uint8_t *)p, .len = n };
}
nst_slice nst_slice_str(const char *s); /* без завершающего нуля */

#endif /* NESTOR_NESTOR_H */
