using System.Security.Claims;
using Microsoft.IdentityModel.JsonWebTokens;

namespace CourseFlow.Api.Common.Auth;

/// <summary>
/// Текущий пользователь запроса (Глава 13.6). Абстракция над ClaimsPrincipal:
/// сервисы не знают про HttpContext и легко тестируются с FakeCurrentUser.
/// </summary>
public interface ICurrentUser
{
    /// <summary>Идентификатор пользователя или null, если запрос анонимный.</summary>
    Guid? UserId { get; }

    /// <summary>Email из токена или null для анонимного запроса.</summary>
    string? Email { get; }

    bool IsAuthenticated { get; }

    bool IsInRole(string role);
}

public sealed class HttpContextCurrentUser(IHttpContextAccessor accessor) : ICurrentUser
{
    private ClaimsPrincipal? Principal => accessor.HttpContext?.User;

    public bool IsAuthenticated => Principal?.Identity?.IsAuthenticated ?? false;

    public Guid? UserId
    {
        get
        {
            // MapInboundClaims = false, поэтому claim называется "sub", а не NameIdentifier
            var sub = Principal?.FindFirstValue(JwtRegisteredClaimNames.Sub);
            return Guid.TryParse(sub, out var id) ? id : null;
        }
    }

    public string? Email => Principal?.FindFirstValue(JwtRegisteredClaimNames.Email);

    public bool IsInRole(string role) => Principal?.IsInRole(role) ?? false;
}

/// <summary>Расширения для случаев, когда endpoint защищён RequireAuthorization и пользователь гарантированно есть.</summary>
public static class CurrentUserExtensions
{
    /// <summary>
    /// Идентификатор аутентифицированного пользователя. Бросает, если вызван на анонимном
    /// запросе: это ошибка программиста (забыли RequireAuthorization), а не пользователя.
    /// </summary>
    public static Guid RequiredUserId(this ICurrentUser user) =>
        user.UserId ?? throw new InvalidOperationException(
            "Current user is not authenticated. The endpoint must require authorization.");
}
