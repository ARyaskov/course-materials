using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.SignalR;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;

namespace CourseFlow.Api.Common.Auth;

public static class AuthExtensions
{
    /// <summary>
    /// Одна конфигурация JWT для всех трёх интерфейсов — REST, GraphQL и SignalR (Глава 13.8).
    /// </summary>
    public static IServiceCollection AddJwtAuthentication(
        this IServiceCollection services, IConfiguration configuration)
    {
        services.AddOptions<JwtOptions>()
            .Bind(configuration.GetSection(JwtOptions.SectionName))
            .ValidateDataAnnotations()
            .ValidateOnStart();

        var jwt = configuration.GetSection(JwtOptions.SectionName).Get<JwtOptions>()
                  ?? throw new InvalidOperationException("Section 'Jwt' is missing in configuration");

        services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
            .AddJwtBearer(options =>
            {
                // Не переименовывать claims в длинные URI из WS-Federation:
                // "sub" остаётся "sub", "email" — "email"
                options.MapInboundClaims = false;

                options.TokenValidationParameters = new TokenValidationParameters
                {
                    ValidateIssuer = true,
                    ValidIssuer = jwt.Issuer,
                    ValidateAudience = true,
                    ValidAudience = jwt.Audience,
                    ValidateLifetime = true,
                    ValidateIssuerSigningKey = true,
                    IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt.SecretKey)),
                    // Допуск на рассинхронизацию часов: по умолчанию 5 минут — слишком много для 15-минутного токена
                    ClockSkew = TimeSpan.FromSeconds(30),
                    NameClaimType = JwtRegisteredClaimNames.Sub,
                    RoleClaimType = ClaimTypes.Role
                };

                // SignalR: браузерный WebSocket не умеет ставить заголовок Authorization,
                // поэтому клиент передаёт токен в query string. Разрешаем это ТОЛЬКО для /hubs (Глава 13.8)
                options.Events = new JwtBearerEvents
                {
                    OnMessageReceived = context =>
                    {
                        var accessToken = context.Request.Query["access_token"];
                        var path = context.HttpContext.Request.Path;

                        if (!string.IsNullOrEmpty(accessToken) && path.StartsWithSegments("/hubs"))
                            context.Token = accessToken;

                        return Task.CompletedTask;
                    }
                };
            });

        // Policy-based authorization (Глава 13.7): endpoints ссылаются на имена политик,
        // а не на конкретные роли — правила меняются в одном месте
        services.AddAuthorizationBuilder()
            .AddPolicy("Instructor", p => p.RequireRole("Instructor", "Admin"))
            .AddPolicy("Admin", p => p.RequireRole("Admin"));

        services.AddHttpContextAccessor();
        services.AddScoped<ICurrentUser, HttpContextCurrentUser>();
        services.AddSingleton<JwtService>();
        services.AddSingleton<IPasswordHasher, BcryptPasswordHasher>();

        // SignalR адресует пользователей по IUserIdProvider; по умолчанию это NameIdentifier,
        // а у нас идентификатор лежит в "sub"
        services.AddSingleton<IUserIdProvider, SubClaimUserIdProvider>();

        return services;
    }
}

/// <summary>Clients.User(userId) в SignalR будет работать по claim "sub" (Глава 12.6).</summary>
public sealed class SubClaimUserIdProvider : IUserIdProvider
{
    public string? GetUserId(HubConnectionContext connection) =>
        connection.User?.FindFirstValue(JwtRegisteredClaimNames.Sub);
}
