using CourseFlow.Api.Common.Auth;
using CourseFlow.Api.Common.Errors;
using CourseFlow.Api.Modules.Notifications.Services;

namespace CourseFlow.Api.Modules.Notifications.Endpoints;

public static class NotificationsModule
{
    public static IServiceCollection AddNotificationsModule(this IServiceCollection services)
    {
        services.AddScoped<NotificationService>();
        services.AddScoped<INotificationDispatcher, SignalRNotificationDispatcher>();
        return services;
    }

    public static IEndpointRouteBuilder MapNotifications(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/v1/notifications")
            .RequireAuthorization()
            .WithTags("Notifications");

        group.MapGet("/", GetMyNotificationsAsync).Produces<IReadOnlyList<NotificationDto>>();
        group.MapGet("/unread-count", GetUnreadCountAsync).Produces<UnreadCountDto>();
        group.MapPut("/{id:guid}/read", MarkAsReadAsync).Produces(StatusCodes.Status204NoContent);
        group.MapPut("/read-all", MarkAllAsReadAsync).Produces(StatusCodes.Status204NoContent);

        // SignalR hub (Глава 12): токен для WebSocket приходит в query string access_token
        app.MapHub<NotificationHub>("/hubs/notifications").RequireAuthorization();

        return app;
    }

    private static async Task<IResult> GetMyNotificationsAsync(
        NotificationService service, ICurrentUser currentUser, CancellationToken ct,
        bool unreadOnly = false, int limit = 50)
    {
        limit = Math.Clamp(limit, 1, 200);
        return Results.Ok(await service.GetUserNotificationsAsync(currentUser.RequiredUserId(), unreadOnly, limit, ct));
    }

    private static async Task<IResult> GetUnreadCountAsync(
        NotificationService service, ICurrentUser currentUser, CancellationToken ct) =>
        Results.Ok(new UnreadCountDto(await service.GetUnreadCountAsync(currentUser.RequiredUserId(), ct)));

    private static async Task<IResult> MarkAsReadAsync(
        Guid id, NotificationService service, ICurrentUser currentUser, CancellationToken ct)
    {
        var result = await service.MarkAsReadAsync(id, currentUser.RequiredUserId(), ct);
        return result.ToHttpResult(Results.NoContent());
    }

    private static async Task<IResult> MarkAllAsReadAsync(
        NotificationService service, ICurrentUser currentUser, CancellationToken ct)
    {
        await service.MarkAllAsReadAsync(currentUser.RequiredUserId(), ct);
        return Results.NoContent();
    }
}
