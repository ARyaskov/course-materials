// Waybill.Migrator — применяет sql/**/*.sql к SQL Server 2025 в лексикографическом порядке.
// Та же логика, что в scripts/apply.ps1: разбиение по GO, журнал dbo.SchemaMigrations, пропуск применённых.
//
//   dotnet run --project src/Waybill.Migrator -- --sql ./sql
//   dotnet run --project src/Waybill.Migrator -- --sql ./sql --only 03-schema --force
//   dotnet run --project src/Waybill.Migrator -- --sql ./sql --skip 16-ops
//   WAYBILL_CONNECTION="Server=localhost,1433;User ID=sa;Password=...;Encrypt=Mandatory;TrustServerCertificate=true" dotnet run ...
//
// Строка подключения: аргумент --connection, иначе переменная окружения WAYBILL_CONNECTION,
// иначе локальный экземпляр с Windows-аутентификацией. База в строке игнорируется: подключаемся к master,
// потому что 001_database.sql создаёт базу, а USE внутри файлов переключает контекст.
// Логика — в MigrationRunner (Migrator.cs), чтобы тесты (Testcontainers, глава 16) применяли те же скрипты без отдельного процесса.

using Waybill.Migrator;

MigratorOptions options;
try { options = MigratorOptions.Parse(args); }
catch (ArgumentException ex) { Console.Error.WriteLine(ex.Message); return 2; }

var result = await MigrationRunner.RunAsync(options, Console.Out, Console.Error);
return result.ExitCode;
