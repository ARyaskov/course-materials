using CourseFlow.Api.Infrastructure.Data;
using CourseFlow.Api.Modules.Notifications.Domain;
using CourseFlow.Api.Modules.Notifications.Services;
using CourseFlow.Contracts;
using MassTransit;
using Microsoft.EntityFrameworkCore;

namespace CourseFlow.Api.Modules.Notifications.Consumers;

// Имена consumer-ов уникальны в пределах приложения: MassTransit строит имя очереди
// из имени класса, и два EnrollmentCreatedConsumer в разных модулях получили бы одну очередь.

/// <summary>Реагируем на публикацию курса: уведомляем подписчиков автора.</summary>
public sealed class CoursePublishedConsumer(
    AppDbContext db,
    INotificationDispatcher dispatcher,
    ILogger<CoursePublishedConsumer> logger) : IConsumer<CoursePublished>
{
    public async Task Consume(ConsumeContext<CoursePublished> context)
    {
        var msg = context.Message;
        var ct = context.CancellationToken;

        // Получаем подписчиков автора
        var subscriberIds = await db.UserFollows
            .Where(f => f.FollowedUserId == msg.AuthorId)
            .Select(f => f.FollowerId)
            .ToListAsync(ct);

        if (subscriberIds.Count == 0) return;

        var notifications = subscriberIds.Select(userId =>
            Notification.Create(
                userId,
                "Новый курс",
                $"Вышел новый курс: {msg.Title}",
                NotificationType.CoursePublished,
                $"/courses/{msg.CourseId}"))
            .ToList();

        db.Notifications.AddRange(notifications);
        await db.SaveChangesAsync(ct);

        // Отправляем через WebSocket тем, кто онлайн
        foreach (var notification in notifications)
        {
            await dispatcher.SendToUserAsync(
                notification.UserId, NotificationDto.FromDomain(notification), ct);
        }

        logger.LogInformation("Sent {Count} notifications for course {CourseId}", notifications.Count, msg.CourseId);
    }
}

/// <summary>Реагируем на создание зачисления: подтверждение записи.</summary>
public sealed class EnrollmentNotificationConsumer(
    AppDbContext db,
    INotificationDispatcher dispatcher) : IConsumer<EnrollmentCreated>
{
    public async Task Consume(ConsumeContext<EnrollmentCreated> context)
    {
        var msg = context.Message;
        var ct = context.CancellationToken;

        var course = await db.Courses.AsNoTracking()
            .FirstOrDefaultAsync(c => c.Id == msg.CourseId, ct);

        if (course is null) return;

        var notification = Notification.Create(
            msg.UserId,
            "Запись подтверждена",
            $"Вы успешно записались на курс: {course.Title}",
            NotificationType.EnrollmentConfirmed,
            $"/courses/{msg.CourseId}");

        db.Notifications.Add(notification);
        await db.SaveChangesAsync(ct);

        await dispatcher.SendToUserAsync(msg.UserId, NotificationDto.FromDomain(notification), ct);
    }
}

/// <summary>Реагируем на завершение курса.</summary>
public sealed class CourseCompletedNotificationConsumer(
    AppDbContext db,
    INotificationDispatcher dispatcher) : IConsumer<CourseCompleted>
{
    public async Task Consume(ConsumeContext<CourseCompleted> context)
    {
        var msg = context.Message;
        var ct = context.CancellationToken;

        var title = await db.Courses.AsNoTracking()
            .Where(c => c.Id == msg.CourseId)
            .Select(c => c.Title)
            .FirstOrDefaultAsync(ct);

        if (title is null) return;

        var notification = Notification.Create(
            msg.UserId,
            "Курс пройден",
            $"Поздравляем! Вы завершили курс: {title}",
            NotificationType.CourseCompleted,
            $"/courses/{msg.CourseId}");

        db.Notifications.Add(notification);
        await db.SaveChangesAsync(ct);

        await dispatcher.SendToUserAsync(msg.UserId, NotificationDto.FromDomain(notification), ct);
    }
}
