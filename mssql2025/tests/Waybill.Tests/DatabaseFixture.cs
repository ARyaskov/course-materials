// Интеграционные тесты против SQL Server 2025. Два режима (WAYBILL_TEST_MODE):
//   local (по умолчанию) — существующая база Waybill (после ./scripts/apply.ps1); если недоступна — тесты пропускаются с сообщением;
//   container            — Testcontainers поднимает mcr.microsoft.com/mssql/server:2025-latest и применяет sql/** мигратором (глава 16).
using Dapper;
using DotNet.Testcontainers.Builders;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Testcontainers.MsSql;
using Waybill.Data;
using Waybill.Migrator;
using Xunit;

namespace Waybill.Tests;

public sealed class DatabaseFixture : IAsyncLifetime
{
    private MsSqlContainer? _container;

    public string ConnectionString { get; private set; } = Environment.GetEnvironmentVariable("WAYBILL_CONNECTION")
        ?? "Server=localhost;Database=Waybill;Integrated Security=true;Encrypt=Mandatory;TrustServerCertificate=true";

    public string Mode { get; } = Environment.GetEnvironmentVariable("WAYBILL_TEST_MODE") ?? "local";
    public bool Available { get; private set; }
    public string? Reason { get; private set; }
    public IDbConnectionFactory Factory { get; private set; } = null!;

    public async Task InitializeAsync()
    {
        JsonParameters.Register();
        if (Mode.Equals("container", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                await StartContainerAndMigrateAsync();
            }
            catch (Exception ex)
            {
                Available = false;
                Reason = $"контейнер не поднялся: {ex.GetType().Name} {ex.Message}";
                return;
            }
        }

        Factory = new SqlConnectionFactory(Options.Create(new WaybillDbOptions { ConnectionString = ConnectionString, ApplicationName = "Waybill.Tests", TransientRetryCount = 1 }),
            NullLogger<SqlConnectionFactory>.Instance);
        try
        {
            await using var conn = await Factory.OpenAsync();
            var ok = await conn.ExecuteScalarAsync<int>("SELECT IIF(OBJECT_ID(N'ops.usp_IngestTrackingEvents') IS NULL, 0, 1)");
            Available = ok == 1;
            Reason = ok == 1 ? null : "процедуры Waybill не найдены: выполните ./scripts/apply.ps1";
        }
        catch (SqlException ex)
        {
            Available = false;
            Reason = $"база недоступна: {ex.Number} {ex.Message}";
        }
        catch (Exception ex)
        {
            Available = false;
            Reason = $"подключение не удалось: {ex.GetType().Name} {ex.Message}";
        }
    }

    /// <summary>SQL Server 2025 в контейнере + миграции: те же скрипты, что и на стенде; 16-ops (бэкапы, Agent) пропускается.</summary>
    private async Task StartContainerAndMigrateAsync()
    {
        _container = new MsSqlBuilder("mcr.microsoft.com/mssql/server:2025-latest")
            .WithPassword("Waybill_Test_2025!")
            .WithEnvironment("MSSQL_PID", "Developer")
            .WithEnvironment("MSSQL_COLLATION", "Latin1_General_100_CI_AS_SC_UTF8")
            .WithEnvironment("MSSQL_AGENT_ENABLED", "false")
            .WithWaitStrategy(Wait.ForUnixContainer().UntilMessageIsLogged("Recovery is complete"))
            .Build();
        await _container.StartAsync();

        var master = new SqlConnectionStringBuilder(_container.GetConnectionString()) { TrustServerCertificate = true, Encrypt = SqlConnectionEncryptOption.Mandatory };
        var sqlRoot = FindSqlRoot();
        var options = new MigratorOptions { SqlRoot = sqlRoot, ConnectionString = master.ConnectionString, CommandTimeoutSeconds = 900 };
        options.Skip.AddRange(["16-ops"]);
        var result = await MigrationRunner.RunAsync(options, TextWriter.Null, Console.Error);
        if (result.ExitCode != 0)
            throw new InvalidOperationException($"миграции не применились: {result.FailedScript} (exit {result.ExitCode})");

        ConnectionString = new SqlConnectionStringBuilder(master.ConnectionString) { InitialCatalog = "Waybill" }.ConnectionString;
    }

    private static string FindSqlRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !Directory.Exists(Path.Combine(dir.FullName, "sql")))
            dir = dir.Parent;
        return dir is null ? throw new DirectoryNotFoundException("папка sql/ не найдена выше каталога тестов") : Path.Combine(dir.FullName, "sql");
    }

    public async Task DisposeAsync()
    {
        if (_container is not null) await _container.DisposeAsync();
    }

    /// <summary>xunit 2 не умеет пропускать тест во время выполнения: при недоступной базе тест выводит причину и завершается успешно.</summary>
    public bool Ready(Xunit.Abstractions.ITestOutputHelper output)
    {
        if (!Available) output.WriteLine("SKIP: " + Reason);
        return Available;
    }
}

[CollectionDefinition("db")]
public sealed class DatabaseCollection : ICollectionFixture<DatabaseFixture>;
