using CourseFlow.Api.Common.Errors;
using CourseFlow.Api.Modules.Notifications.Domain;

namespace CourseFlow.Api.Modules.Notifications;

public record NotificationDto(
    Guid Id,
    string Title,
    string Body,
    string Type,
    bool IsRead,
    DateTimeOffset CreatedAt,
    DateTimeOffset? ReadAt,
    string? ActionUrl)
{
    public static NotificationDto FromDomain(Notification n) =>
        new(n.Id, n.Title, n.Body, n.Type.ToString(), n.IsRead, n.CreatedAt, n.ReadAt, n.ActionUrl);
}

public record UnreadCountDto(int Count);

public static class NotificationErrors
{
    public static Error NotFound(Guid id) =>
        new("Notification.NotFound", $"Notification '{id}' was not found", ErrorType.NotFound);
}
