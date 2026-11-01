using System.Security.Cryptography;
using System.Text;
using Microsoft.IdentityModel.Tokens;

namespace CourseFlow.Api.Modules.Users.Domain;

public enum UserRole { Student, Instructor, Admin }

/// <summary>Пользователь платформы (Глава 23.2). Инварианты — внутри сущности, сеттеры приватные.</summary>
public class User
{
    public Guid Id { get; private set; } = Guid.CreateVersion7();
    public string Email { get; private set; } = null!;
    public string PasswordHash { get; private set; } = null!;
    public string FirstName { get; private set; } = null!;
    public string LastName { get; private set; } = null!;
    public UserRole Role { get; private set; } = UserRole.Student;
    public DateTimeOffset CreatedAt { get; private set; } = DateTimeOffset.UtcNow;
    public bool IsActive { get; private set; } = true;

    private readonly List<RefreshToken> _refreshTokens = [];
    public IReadOnlyList<RefreshToken> RefreshTokens => _refreshTokens;

    private User() { } // EF Core

    public static User Create(string email, string passwordHash, string firstName, string lastName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(email);
        ArgumentException.ThrowIfNullOrWhiteSpace(passwordHash);
        ArgumentException.ThrowIfNullOrWhiteSpace(firstName);
        ArgumentException.ThrowIfNullOrWhiteSpace(lastName);

        return new User
        {
            Email = email.Trim().ToLowerInvariant(),
            PasswordHash = passwordHash,
            FirstName = firstName.Trim(),
            LastName = lastName.Trim()
        };
    }

    /// <summary>
    /// Выдаёт новый refresh-токен. Возвращает открытое значение — оно уходит клиенту
    /// и нигде больше не сохраняется: в базе лежит только хеш.
    /// </summary>
    public (string Value, RefreshToken Entity) IssueRefreshToken(TimeSpan lifetime)
    {
        var value = Base64UrlEncoder.Encode(RandomNumberGenerator.GetBytes(64));
        var token = RefreshToken.Issue(Id, RefreshToken.Hash(value), lifetime);

        _refreshTokens.Add(token);
        return (value, token);
    }

    /// <summary>Отзывает все активные токены — при смене пароля и при reuse detection.</summary>
    public void RevokeAllRefreshTokens()
    {
        foreach (var token in _refreshTokens.Where(t => t.IsActive))
            token.Revoke();
    }

    public void SetRole(UserRole role) => Role = role;

    public void Deactivate() => IsActive = false;
}

public class RefreshToken
{
    public Guid Id { get; private set; } = Guid.CreateVersion7();
    public Guid UserId { get; private set; }

    // В базе хранится ХЕШ токена, а не сам токен: утечка дампа
    // не даст злоумышленнику действующих сессий (Глава 13.5)
    public string TokenHash { get; private set; } = null!;

    public DateTimeOffset ExpiresAt { get; private set; }
    public DateTimeOffset? RevokedAt { get; private set; }

    public bool IsRevoked => RevokedAt is not null;
    public bool IsExpired => ExpiresAt <= DateTimeOffset.UtcNow;
    public bool IsActive => !IsRevoked && !IsExpired;

    private RefreshToken() { } // EF Core

    public static RefreshToken Issue(Guid userId, string tokenHash, TimeSpan lifetime) => new()
    {
        UserId = userId,
        TokenHash = tokenHash,
        ExpiresAt = DateTimeOffset.UtcNow.Add(lifetime)
    };

    // Быстрый хеш достаточен: токен создан криптографическим генератором
    // и содержит 512 бит энтропии — перебирать его бессмысленно
    public static string Hash(string token) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token)));

    public void Revoke() => RevokedAt ??= DateTimeOffset.UtcNow;
}

/// <summary>Подписка на автора (Глава 9.11): подписчики получают уведомление CoursePublished.</summary>
public class UserFollow
{
    public Guid FollowerId { get; private set; }
    public Guid FollowedUserId { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; } = DateTimeOffset.UtcNow;

    private UserFollow() { } // EF Core

    public static UserFollow Create(Guid followerId, Guid followedUserId)
    {
        if (followerId == followedUserId)
            throw new ArgumentException("A user cannot follow themselves");

        return new UserFollow { FollowerId = followerId, FollowedUserId = followedUserId };
    }
}
