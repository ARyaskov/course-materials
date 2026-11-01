// Повторы на уровне единицы работы: deadlock (1205) и обновление конфликтующих версий — повторяем всю операцию,
// а не одну команду; таймаут (-2) не повторяем автоматически — это сигнал о нагрузке или блокировке.
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;

namespace Waybill.Data;

public static class SqlErrors
{
    public const int Deadlock = 1205;
    /// <summary>Temporal: конкурентное обновление одной строки — время транзакции раньше ValidFrom текущей версии (глава 11); повторяется как deadlock.</summary>
    public const int TemporalTimeConflict = 13535;
    public const int Timeout = -2;
    public const int UniqueViolation = 2627;
    public const int UniqueIndexViolation = 2601;
    public const int ConstraintViolation = 547;

    // Ошибки приложения (docs/errors.md)
    public const int NotFound = 50001;
    public const int UnknownCarrier = 50031;
    public const int WebhookNotJson = 50030;
    public const int WebhookBadStructure = 50032;
    public const int WebhookNoEvents = 50033;
    public const int UnknownMerchant = 50050;
    public const int BadTrackingFormat = 50051;
    public const int AppLockTimeout = 50061;
    public const int VersionConflict = 50070;
    /// <summary>RLS: BLOCK-предикат отверг строку чужого арендатора (глава 15).</summary>
    public const int RlsBlocked = 33504;
    /// <summary>Нет прав на объект / столбец — роль waybill_api вышла за разрешённый набор.</summary>
    public const int PermissionDenied = 229;
    public const int ColumnPermissionDenied = 230;
    /// <summary>ship.usp_ListShipmentsSorted: столбец или направление сортировки вне белого списка.</summary>
    public const int BadSortColumn = 50095;
    public const int BadSortDirection = 50096;
    /// <summary>bill.usp_GenerateInvoice / usp_IssueInvoice: счёт уже выставлен (глава 17).</summary>
    public const int InvoiceAlreadyIssued = 50110;
    public const int InvoiceNotDraft = 50111;

    public static bool IsDeadlock(this SqlException ex) => ex.Number is Deadlock or TemporalTimeConflict;
    public static bool IsTimeout(this SqlException ex) => ex.Number == Timeout;
    public static bool IsUniqueViolation(this SqlException ex) => ex.Number is UniqueViolation or UniqueIndexViolation;
}

public static class Resilience
{
    /// <summary>Повторить единицу работы при deadlock: до maxAttempts, пауза 50·2ⁿ мс с джиттером. Операция обязана быть идемпотентной или атомарной.</summary>
    public static async Task<T> RetryOnDeadlockAsync<T>(Func<CancellationToken, Task<T>> unitOfWork, ILogger logger,
        int maxAttempts = 3, CancellationToken ct = default)
    {
        for (var attempt = 1; ; attempt++)
        {
            try
            {
                return await unitOfWork(ct);
            }
            catch (SqlException ex) when (ex.IsDeadlock() && attempt < maxAttempts)
            {
                var delay = TimeSpan.FromMilliseconds(50 * Math.Pow(2, attempt - 1) + Random.Shared.Next(0, 50));
                logger.LogWarning("Retryable conflict ({Number}), retry {Attempt}/{Max} after {Delay}", ex.Number, attempt, maxAttempts, delay);
                await Task.Delay(delay, ct);
            }
        }
    }

    public static Task RetryOnDeadlockAsync(Func<CancellationToken, Task> unitOfWork, ILogger logger, int maxAttempts = 3, CancellationToken ct = default) =>
        RetryOnDeadlockAsync(async token => { await unitOfWork(token); return true; }, logger, maxAttempts, ct);
}
