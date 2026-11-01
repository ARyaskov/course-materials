using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using Microsoft.IdentityModel.JsonWebTokens;

namespace CourseFlow.Api.Modules.Notifications.Services;

/// <summary>Real-time доставка уведомлений. Абстракция нужна, чтобы consumer-ы не зависели от SignalR.</summary>
public interface INotificationDispatcher
{
    Task SendToUserAsync(Guid userId, NotificationDto notification, CancellationToken ct);
}

public sealed class SignalRNotificationDispatcher(IHubContext<NotificationHub> hubContext) : INotificationDispatcher
{
    public Task SendToUserAsync(Guid userId, NotificationDto notification, CancellationToken ct) =>
        // Clients.User адресует все соединения пользователя; идентификатор берёт SubClaimUserIdProvider.
        // Если пользователь офлайн — сообщение просто никому не уйдёт, оно уже сохранено в БД
        hubContext.Clients.User(userId.ToString()).SendAsync("notification", notification, ct);
}

/// <summary>
/// SignalR hub уведомлений (Глава 12). Экземпляр hub создаётся на каждый вызов метода,
/// поэтому состояние в полях хранить нельзя; пользователь — через Context.User, не через IHttpContextAccessor.
/// </summary>
[Authorize]
public sealed class NotificationHub : Hub
{
    public override async Task OnConnectedAsync()
    {
        var userId = Context.User?.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;

        // Группа на пользователя — альтернатива Clients.User для рассылок по подмножеству
        if (userId is not null)
            await Groups.AddToGroupAsync(Context.ConnectionId, $"user:{userId}");

        await base.OnConnectedAsync();
    }

    /// <summary>Клиент может запросить подтверждение соединения (полезно для отладки транспорта).</summary>
    public Task<string> Ping() => Task.FromResult("pong");
}
