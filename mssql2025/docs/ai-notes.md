# AI-функции Waybill: заметки по главе 14

## Реестр настроек (`ops.Setting`)

| Имя | По умолчанию | Смысл |
| --- | --- | --- |
| `ai.enabled` | `0` | `1` — векторы считает внешняя модель (`WaybillEmbeddings`), `0` — `ops.fn_ToyEmbedding` (hash bag-of-words, модель `toy-hash-768`) |
| `ai.embeddings.url` | `http://localhost:11434/api/embed` | адрес Ollama; из контейнера SQL Server — `host.docker.internal:11434` |
| `ai.embeddings.model` | `nomic-embed-text` | имя модели; хранится в `EmbeddingModel` каждой строки, входит в предикаты поиска |
| `ai.embeddings.dimensions` | `768` | размерность `vector(768)`; смена модели с другой размерностью = новый столбец + пересчёт |
| `ai.vector_index` | `0` | `1` — `040_vector_index.sql` создаёт DiskANN-индекс; **таблица становится только для чтения (preview)** — на `ops.Incident` не включать |

Приложение: секция `Ai` в `appsettings.json` (`Enabled`, `EmbeddingsUrl`, `Model`, `Dimensions`, `TimeoutSeconds`). При `Ai:Enabled = true` вектор запроса/нового инцидента считает `EmbeddingService` (Ollama `/api/embed`), при `false` или ошибке — передаёт `NULL`, и сервер считает сам (`usp_EmbedText`, `usp_EmbedPendingIncidents`). Рассогласование настроек базы и API допустимо: результат корректный, но медленнее.

## Объекты

| Объект | Файл | Назначение |
| --- | --- | --- |
| `ops.Incident.Embedding vector(768)`, `EmbeddingModel`, `EmbeddedAt` | `010` | вектор документа (заголовок + начало описания) |
| `IX_Incident_Embedding_Pending` (filtered `Embedding IS NULL`) | `010` | очередь на вычисление |
| `ops.IncidentChunk` | `010` | чанки описаний с собственными векторами; `ON DELETE CASCADE` |
| `ops.fn_ToyEmbedding` | `010` | детерминированный toy-вектор для стенда без модели |
| `ops.usp_EmbedPendingIncidents @BatchSize` | `010` | пересчёт очереди моделью или toy; вызывать циклом (фон, Agent) |
| `WaybillEmbeddings` (EXTERNAL MODEL, API_FORMAT Ollama) | `020` | создаётся только при `ai.enabled = 1` |
| `ops.usp_ChunkIncident @IncidentId, @ChunkSize, @Overlap` | `020` | `AI_GENERATE_CHUNKS` (preview) в TRY, иначе `SUBSTRING` + `GENERATE_SERIES` |
| `ops.usp_EmbedText @Text, @Embedding OUT, @Model OUT` | `030` | вектор произвольного текста той же моделью, что данные |
| `ops.usp_FindSimilarIncidents @IncidentId, @Top, @MaxDistance, @SameCarrier` | `030` | точный kNN; фильтры по магазину/перевозчику до расстояний |
| `ops.usp_SearchIncidentsHybrid @MerchantId, @Query, @QueryEmbedding, @Top` | `030` | full-text (`usp_SearchIncidents`) + kNN → RRF (k = 60) |
| `VIX_Incident_Embedding` (DiskANN, preview) | `040` | только при `ai.vector_index = 1` |
| `ops.usp_FindSimilarIncidentsAnn` | `040` | `VECTOR_SEARCH` через `sp_executesql` при наличии индекса, иначе точный поиск; `TOP_N = @Top × 4` |

API: `GET /incidents/{id}/similar?top&sameCarrier&approximate`, `GET /merchants/{id}/incidents/search?q&top`, `POST /incidents` (`IncidentRepository`, `EmbeddingService`).

## Правила

* Все векторные запросы фильтруют по `MerchantId` **до** вычисления расстояний; тест изоляции (14.9) — обязателен для любой новой процедуры.
* `EmbeddingModel = @model` во всех предикатах: векторы разных моделей несравнимы и не дают ошибки.
* Векторы записываются нормализованными (`VECTOR_NORMALIZE`); проверка `VECTOR_NORM(...) ≈ 1` — часть drift-check (глава 16).
* Внешняя модель не вызывается синхронно в HTTP-запросе на стороне базы: вектор считает приложение с таймаутом и деградацией, пересчёты — фоновые батчи (100 строк, пауза 2 с).
* Секреты провайдеров — только `DATABASE SCOPED CREDENTIAL` / менеджер секретов приложения.
* Preview-функции (`AI_GENERATE_CHUNKS`, `CREATE VECTOR INDEX`, `VECTOR_SEARCH`) изолированы в TRY/CATCH и динамическом SQL; скрипты завершаются на стенде без `PREVIEW_FEATURES`.

## Замеры

Заполняется по уроку 14.9 (`check.sql`, `SET STATISTICS TIME`).

| Сценарий | Строк в магазине | Время, мс | Logical reads | Примечание |
| --- | --- | --- | --- | --- |
| kNN точный, стенд (20 инцидентов) | | | | база |
| kNN точный, 100k, без индекса | ~33 000 | | | скан кластерного |
| kNN точный, 100k, покрывающий индекс | ~33 000 | | | |
| гибрид, 100k (FT / kNN / RRF) | ~33 000 | | | |
| модель: 1 000 инцидентов батчами по 100 | — | | — | Ollama |
| DiskANN на снимке 200k: построение, recall@5/@10 | — | | — | только на снимке |

## Почему индекс не включён на `ops.Incident`

Векторный индекс в preview делает таблицу только для чтения, а `ops.Incident` пишется постоянно. Точный kNN по магазину укладывается в бюджет до сотен тысяч инцидентов на магазин. Схема на будущее: `ops.IncidentArchive` (старше 90 дней) с индексом, пересоздаваемым ночью (`DROP INDEX` → догрузка → `CREATE VECTOR INDEX`), горячие строки — точным поиском, объединение результатов в приложении. Переключение `ops.Incident` на ANN — после снятия read-only-ограничения в GA.
