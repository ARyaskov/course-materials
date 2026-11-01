-- Pulse: выгрузка месяца событий в Parquet-архив (глава 6).
-- INTO OUTFILE пишет на стороне клиента, поэтому с Docker-стендом удобнее
-- перенаправить поток вывода клиента в файл на хосте:
--
--   docker exec -i pulse-clickhouse clickhouse-client \
--     --user analyst --password analyst --database pulse \
--     --param_month=202605 \
--     --query "$(sed -n '/^SELECT/,/^SETTINGS.*;$/p' ingestion/export_month.sql)" \
--     > ingestion/files/archive-202605.parquet
--
-- Обратное чтение: SELECT count() FROM file('pulse/archive-202605.parquet', Parquet);

SELECT *
FROM pulse.events
WHERE toYYYYMM(event_time) = {month:UInt32}
ORDER BY event_time
FORMAT Parquet
SETTINGS output_format_parquet_compression_method = 'zstd',
         output_format_parquet_row_group_size = 500000,
         output_format_parquet_string_as_string = 1;
