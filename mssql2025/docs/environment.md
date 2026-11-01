# Стенд автора курса

| Параметр | Значение |
| --- | --- |
| Экземпляр | `MSSQL17.MSSQLSERVER` (экземпляр по умолчанию, `localhost`) |
| Версия | SQL Server 2025 (17.x), Developer Edition |
| Платформа | Windows 11 |
| Аутентификация | Windows (`Integrated Security=true`) |
| Коллация экземпляра | заполняется по результату `SERVERPROPERTY('Collation')` |
| Пути по умолчанию | `SERVERPROPERTY('InstanceDefaultDataPath')` / `InstanceDefaultLogPath` |
| tempdb | число файлов — по результату `sys.master_files WHERE database_id = 2` |
| Альтернатива | `docker compose up -d` → `mcr.microsoft.com/mssql/server:2025-latest`, порт 1433, `sa` |

## База по умолчанию против Waybill (задание 1.4)

| Настройка | `CREATE DATABASE X;` (из model) | Waybill |
| --- | --- | --- |
| compatibility_level | 170 (наследуется от model) | 170 (явно) |
| collation | коллация экземпляра | `Latin1_General_100_CI_AS_SC_UTF8` |
| рост файлов | 64 MB (model) | данные 256/512 MB, журнал 256 MB |
| READ_COMMITTED_SNAPSHOT | OFF | ON |
| ACCELERATED_DATABASE_RECOVERY | OFF | ON |
| OPTIMIZED_LOCKING | OFF | ON |
| QUERY_STORE | OFF (model) | ON, READ_WRITE, 1024 MB, ожидания включены |
| AUTO_UPDATE_STATISTICS_ASYNC | OFF | ON |
