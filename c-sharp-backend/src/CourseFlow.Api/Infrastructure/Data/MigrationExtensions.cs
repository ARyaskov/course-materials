using Microsoft.EntityFrameworkCore;

namespace CourseFlow.Api.Infrastructure.Data;

public static class MigrationExtensions
{
    /// <summary>
    /// Применяет невыполненные миграции (Глава 9.5). Вызывается только вне production:
    /// там схема накатывается отдельным шагом деплоя (Глава 20.7), иначе несколько
    /// инстансов начнут мигрировать одновременно.
    /// </summary>
    public static async Task MigrateAsync(this WebApplication app, CancellationToken ct = default)
    {
        await using var scope = app.Services.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var logger = scope.ServiceProvider.GetRequiredService<ILogger<AppDbContext>>();

        var pending = (await db.Database.GetPendingMigrationsAsync(ct)).ToList();
        if (pending.Count == 0)
        {
            logger.LogInformation("Database is up to date");
            return;
        }

        logger.LogInformation("Applying {Count} pending migration(s): {Migrations}",
            pending.Count, string.Join(", ", pending));

        await db.Database.MigrateAsync(ct);
    }
}
