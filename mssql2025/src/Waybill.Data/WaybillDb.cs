// Waybill.Data — подключение, retry-политика, контекст сессии. Один SqlConnection на единицу работы; пул — у провайдера.
using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Waybill.Data;

/// <summary>Настройки подключения (appsettings: "Waybill").</summary>
public sealed class WaybillDbOptions
{
    public const string SectionName = "Waybill";

    /// <summary>Строка подключения без пароля в репозитории: секреты — через переменные окружения или user-secrets.</summary>
    public string ConnectionString { get; set; } =
        "Server=localhost;Database=Waybill;Integrated Security=true;Encrypt=Mandatory;TrustServerCertificate=true";

    public string ApplicationName { get; set; } = "Waybill.Api";
    public int CommandTimeoutSeconds { get; set; } = 30;

    /// <summary>Повторы на transient-ошибках провайдера (сеть, failover); deadlock и таймауты — отдельно, на уровне единицы работы.</summary>
    public int TransientRetryCount { get; set; } = 3;
}

/// <summary>Фабрика соединений: единственное место, где собирается строка подключения и retry-провайдер.</summary>
public interface IDbConnectionFactory
{
    Task<SqlConnection> OpenAsync(CancellationToken ct = default);
    Task<SqlConnection> OpenAsync(string? user, CancellationToken ct = default);
    /// <summary>Соединение от имени пользователя и арендатора: SESSION_CONTEXT('MerchantId') (read-only) включает фильтр RLS (глава 15).</summary>
    Task<SqlConnection> OpenAsync(string? user, int? merchantId, CancellationToken ct = default);
    int CommandTimeout { get; }
}

public sealed class SqlConnectionFactory : IDbConnectionFactory
{
    private readonly string _connectionString;
    private readonly SqlRetryLogicBaseProvider _retryProvider;
    private readonly ILogger<SqlConnectionFactory> _logger;

    public int CommandTimeout { get; }

    public SqlConnectionFactory(IOptions<WaybillDbOptions> options, ILogger<SqlConnectionFactory> logger)
    {
        var o = options.Value;
        _logger = logger;
        CommandTimeout = o.CommandTimeoutSeconds;

        var builder = new SqlConnectionStringBuilder(o.ConnectionString)
        {
            ApplicationName = o.ApplicationName,          // виден в sys.dm_exec_sessions.program_name и XEvents
            Pooling = true,
            MultipleActiveResultSets = false,             // MARS не нужен: одна команда на соединение
            ConnectTimeout = ConnectTimeoutFor(o.ConnectionString),
        };
        _connectionString = builder.ConnectionString;

        // Transient-ошибки (по списку провайдера: 40613, 40501, 10928, 4060, 233, 64, …) — экспоненциальный backoff.
        // Deadlock 1205 и таймаут (-2) сюда намеренно не входят: их повторяют на уровне единицы работы (Resilience).
        _retryProvider = SqlConfigurableRetryFactory.CreateExponentialRetryProvider(new SqlRetryLogicOption
        {
            NumberOfTries = Math.Max(1, o.TransientRetryCount),
            DeltaTime = TimeSpan.FromMilliseconds(200),
            MaxTimeInterval = TimeSpan.FromSeconds(5),
        });
        _retryProvider.Retrying += (_, e) =>
            _logger.LogWarning(e.Exceptions[^1], "SqlClient retry #{Attempt} after {Delay}", e.RetryCount, e.Delay);

        static int ConnectTimeoutFor(string cs)
        {
            var b = new SqlConnectionStringBuilder(cs);
            return b.ConnectTimeout == 15 ? 10 : b.ConnectTimeout;   // умолчание провайдера 15 с; для API — 10
        }
    }

    public Task<SqlConnection> OpenAsync(CancellationToken ct = default) => OpenAsync(null, ct);

    /// <summary>Открывает соединение и кладёт пользователя в SESSION_CONTEXT('user') — его читают ModifiedBy и RLS (глава 15).</summary>
    public Task<SqlConnection> OpenAsync(string? user, CancellationToken ct = default) => OpenAsync(user, null, ct);

    public async Task<SqlConnection> OpenAsync(string? user, int? merchantId, CancellationToken ct = default)
    {
        var connection = new SqlConnection(_connectionString) { RetryLogicProvider = _retryProvider };
        await connection.OpenAsync(ct);
        if (user is not null)
            await SessionContext.SetUserAsync(connection, user, ct);
        if (merchantId is not null)
            await SessionContext.SetMerchantAsync(connection, merchantId.Value, ct);   // пул сбрасывает контекст при возврате (sp_reset_connection)
        return connection;
    }
}

public static class SessionContext
{
    public static Task<int> SetUserAsync(SqlConnection connection, string user, CancellationToken ct = default) =>
        connection.ExecuteAsync(new CommandDefinition(
            "EXEC sys.sp_set_session_context @key = N'user', @value = @user, @read_only = 0;",
            new { user = new DbString { Value = user, Length = 128 } },
            cancellationToken: ct));

    /// <summary>Арендатор для RLS: read_only — ни одна процедура на этом соединении не сможет его подменить.</summary>
    public static Task<int> SetMerchantAsync(SqlConnection connection, int merchantId, CancellationToken ct = default) =>
        connection.ExecuteAsync(new CommandDefinition(
            "EXEC sys.sp_set_session_context @key = N'MerchantId', @value = @merchantId, @read_only = 1;",
            new { merchantId }, cancellationToken: ct));

    /// <summary>Корреляция с трейсом: sys.dm_exec_sessions.context_info / SESSION_CONTEXT('trace') в XEvents и DMV.</summary>
    public static Task<int> SetTraceAsync(SqlConnection connection, string traceId, CancellationToken ct = default) =>
        connection.ExecuteAsync(new CommandDefinition(
            "EXEC sys.sp_set_session_context @key = N'trace', @value = @trace; DECLARE @ci varbinary(128) = CAST(@trace AS varbinary(128)); SET CONTEXT_INFO @ci;",
            new { trace = new DbString { Value = traceId, IsAnsi = true, Length = 64 } },
            cancellationToken: ct));
}
