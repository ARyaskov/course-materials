using CourseFlow.Api.Common.Auth;
using CourseFlow.Api.Common.Errors;
using CourseFlow.Api.Infrastructure.Data;
using CourseFlow.Api.Modules.Users.Domain;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace CourseFlow.Api.Modules.Users.Services;

/// <summary>Регистрация, вход и ротация refresh-токенов (Глава 13.4–13.5, 23.2).</summary>
public sealed class AuthService(
    AppDbContext db,
    IPasswordHasher passwordHasher,
    JwtService jwtService,
    IOptions<JwtOptions> jwtOptions,
    ILogger<AuthService> logger)
{
    private TimeSpan RefreshLifetime => TimeSpan.FromDays(jwtOptions.Value.RefreshTokenDays);

    public async Task<Result<AuthTokens>> RegisterAsync(RegisterRequest request, CancellationToken ct)
    {
        var email = request.Email.Trim().ToLowerInvariant();

        var exists = await db.Users.AnyAsync(u => u.Email == email, ct);
        if (exists)
            return UserErrors.EmailAlreadyRegistered;

        // Хеш считается ДО создания сущности и передаётся в фабрику.
        // Так невозможно создать пользователя с временным или пустым хешем.
        var passwordHash = passwordHasher.Hash(request.Password);

        var user = User.Create(email, passwordHash, request.FirstName, request.LastName);
        db.Users.Add(user);

        var (refreshValue, _) = user.IssueRefreshToken(RefreshLifetime);
        var accessToken = jwtService.GenerateAccessToken(user);

        await db.SaveChangesAsync(ct);

        logger.LogInformation("User {UserId} registered", user.Id);

        return Result.Success(new AuthTokens(accessToken, refreshValue));
    }

    public async Task<Result<AuthTokens>> LoginAsync(LoginRequest request, CancellationToken ct)
    {
        var email = request.Email.Trim().ToLowerInvariant();

        var user = await db.Users
            .Include(u => u.RefreshTokens)
            .FirstOrDefaultAsync(u => u.Email == email, ct);

        // Одинаковый ответ для "нет пользователя" и "неверный пароль":
        // иначе по разнице ответов можно перебирать зарегистрированные email
        if (user is null || !passwordHasher.Verify(request.Password, user.PasswordHash))
            return UserErrors.InvalidCredentials;

        if (!user.IsActive)
            return UserErrors.Inactive;

        var (refreshValue, _) = user.IssueRefreshToken(RefreshLifetime);
        var accessToken = jwtService.GenerateAccessToken(user);

        await db.SaveChangesAsync(ct);

        return Result.Success(new AuthTokens(accessToken, refreshValue));
    }

    /// <summary>
    /// Ротация refresh-токена с reuse detection (Глава 13.5): старый токен отзывается,
    /// выдаётся новый. Повторное предъявление уже отозванного токена означает,
    /// что он украден — отзываем все сессии пользователя.
    /// </summary>
    public async Task<Result<AuthTokens>> RefreshAsync(RefreshRequest request, CancellationToken ct)
    {
        var hash = RefreshToken.Hash(request.RefreshToken);

        var user = await db.Users
            .Include(u => u.RefreshTokens)
            .FirstOrDefaultAsync(u => u.RefreshTokens.Any(t => t.TokenHash == hash), ct);

        var token = user?.RefreshTokens.FirstOrDefault(t => t.TokenHash == hash);
        if (user is null || token is null)
            return UserErrors.InvalidRefreshToken;

        if (token.IsRevoked)
        {
            logger.LogWarning("Refresh token reuse detected for user {UserId}; revoking all sessions", user.Id);
            user.RevokeAllRefreshTokens();
            await db.SaveChangesAsync(ct);
            return UserErrors.InvalidRefreshToken;
        }

        if (token.IsExpired || !user.IsActive)
            return UserErrors.InvalidRefreshToken;

        token.Revoke();
        var (refreshValue, _) = user.IssueRefreshToken(RefreshLifetime);
        var accessToken = jwtService.GenerateAccessToken(user);

        await db.SaveChangesAsync(ct);

        return Result.Success(new AuthTokens(accessToken, refreshValue));
    }
}
