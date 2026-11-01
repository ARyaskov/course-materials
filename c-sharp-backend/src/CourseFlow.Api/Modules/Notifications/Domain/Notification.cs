namespace CourseFlow.Api.Modules.Notifications.Domain;

public enum NotificationType
{
    CoursePublished,      // новый курс от автора, на которого подписан
    EnrollmentConfirmed,  // подтверждение записи на курс
    CourseCompleted,      // студент завершил курс
    NewLesson,            // новый урок в курсе
    System                // системные уведомления
}

/// <summary>Уведомление (Глава 23.8): хранится в БД и доставляется через SignalR.</summary>
public class Notification
{
    public Guid Id { get; private set; } = Guid.CreateVersion7();
    public Guid UserId { get; private set; }
    public string Title { get; private set; } = null!;
    public string Body { get; private set; } = null!;
    public NotificationType Type { get; private set; }
    public bool IsRead { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? ReadAt { get; private set; }
    public string? ActionUrl { get; private set; }

    private Notification() { } // EF Core

    public static Notification Create(
        Guid userId, string title, string body, NotificationType type, string? actionUrl = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(title);
        ArgumentException.ThrowIfNullOrWhiteSpace(body);

        return new Notification
        {
            UserId = userId,
            Title = title,
            Body = body,
            Type = type,
            ActionUrl = actionUrl
        };
    }

    public void MarkAsRead()
    {
        if (IsRead) return;
        IsRead = true;
        ReadAt = DateTimeOffset.UtcNow;
    }
}
