using CourseFlow.Api.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace CourseFlow.Api.Modules.Users.Infrastructure;

/// <summary>
/// Периодическая очистка истёкших и отозванных refresh-токенов (Глава 16.2–16.3).
/// BackgroundService + PeriodicTimer: задача одна, интервал фиксированный, операция идемпотентна
/// (повторный DELETE ничего не ломает), поэтому Hangfire/Quartz здесь избыточны.
/// </summary>
public sealed class RefreshTokenCleanupWorker(
    IServiceScopeFactory scopeFactory,
    TimeProvider timeProvider,
    ILogger<RefreshTokenCleanupWorker> logger) : BackgroundService
{
    private static readonly TimeSpan Interval = TimeSpan.FromHours(1);
    private static readonly TimeSpan KeepRevokedFor = TimeSpan.FromDays(7); // для расследования reuse detection

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // Первый тик — через Interval, а не сразу: старт приложения не должен ждать очистку
        using var timer = new PeriodicTimer(Interval, timeProvider);

        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                await CleanupAsync(stoppingToken);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                // Не роняем worker: следующая итерация повторит попытку
                logger.LogError(ex, "Refresh token cleanup failed");
            }
        }
    }

    private async Task CleanupAsync(CancellationToken ct)
    {
        // Scope на итерацию: AppDbContext — scoped, а worker — singleton
        await using var scope = scopeFactory.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        var now = timeProvider.GetUtcNow();
        var revokedBefore = now - KeepRevokedFor;

        // Один DELETE без загрузки сущностей (Глава 9.9)
        var deleted = await db.RefreshTokens
            .Where(t => t.ExpiresAt < now || (t.RevokedAt != null && t.RevokedAt < revokedBefore))
            .ExecuteDeleteAsync(ct);

        if (deleted > 0)
            logger.LogInformation("Removed {Count} expired refresh tokens", deleted);
    }
}
