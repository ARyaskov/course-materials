using CourseFlow.Api.Common.Errors;
using CourseFlow.Api.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace CourseFlow.Api.Modules.Notifications.Services;

public sealed class NotificationService(AppDbContext db)
{
    public async Task<IReadOnlyList<NotificationDto>> GetUserNotificationsAsync(
        Guid userId, bool unreadOnly, int limit, CancellationToken ct)
    {
        var query = db.Notifications.AsNoTracking().Where(n => n.UserId == userId);
        if (unreadOnly)
            query = query.Where(n => !n.IsRead);

        return await query
            .OrderByDescending(n => n.CreatedAt)
            .Take(limit)
            .Select(n => new NotificationDto(
                n.Id, n.Title, n.Body, n.Type.ToString(), n.IsRead, n.CreatedAt, n.ReadAt, n.ActionUrl))
            .ToListAsync(ct);
    }

    public async Task<int> GetUnreadCountAsync(Guid userId, CancellationToken ct) =>
        await db.Notifications.CountAsync(n => n.UserId == userId && !n.IsRead, ct);

    public async Task<Result> MarkAsReadAsync(Guid notificationId, Guid userId, CancellationToken ct)
    {
        var notification = await db.Notifications
            .FirstOrDefaultAsync(n => n.Id == notificationId && n.UserId == userId, ct);

        if (notification is null)
            return NotificationErrors.NotFound(notificationId);

        notification.MarkAsRead();
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    /// <summary>ExecuteUpdateAsync (Глава 9.9): один UPDATE вместо загрузки всех сущностей.</summary>
    public async Task<int> MarkAllAsReadAsync(Guid userId, CancellationToken ct)
    {
        var now = DateTimeOffset.UtcNow;
        return await db.Notifications
            .Where(n => n.UserId == userId && !n.IsRead)
            .ExecuteUpdateAsync(s => s
                .SetProperty(n => n.IsRead, true)
                .SetProperty(n => n.ReadAt, now), ct);
    }
}
