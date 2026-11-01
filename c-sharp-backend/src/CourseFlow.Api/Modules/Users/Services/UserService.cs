using CourseFlow.Api.Common.Errors;
using CourseFlow.Api.Infrastructure.Data;
using CourseFlow.Api.Modules.Users.Domain;
using Microsoft.EntityFrameworkCore;

namespace CourseFlow.Api.Modules.Users.Services;

public sealed class UserService(AppDbContext db)
{
    public async Task<Result<UserDto>> GetByIdAsync(Guid userId, CancellationToken ct)
    {
        var user = await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Id == userId, ct);
        return user is null
            ? UserErrors.NotFound(userId)
            : Result.Success(UserDto.FromDomain(user));
    }

    /// <summary>Подписка на автора: подписчики получают уведомления о его новых курсах.</summary>
    public async Task<Result> FollowAsync(Guid followerId, Guid followedUserId, CancellationToken ct)
    {
        if (followerId == followedUserId)
            return UserErrors.CannotFollowSelf;

        if (!await db.Users.AnyAsync(u => u.Id == followedUserId, ct))
            return UserErrors.NotFound(followedUserId);

        var exists = await db.UserFollows.AnyAsync(
            f => f.FollowerId == followerId && f.FollowedUserId == followedUserId, ct);
        if (exists)
            return Result.Success(); // идемпотентно: повторная подписка — не ошибка

        db.UserFollows.Add(UserFollow.Create(followerId, followedUserId));
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    public async Task<Result> UnfollowAsync(Guid followerId, Guid followedUserId, CancellationToken ct)
    {
        // ExecuteDeleteAsync (Глава 9.9): один DELETE без загрузки сущности
        await db.UserFollows
            .Where(f => f.FollowerId == followerId && f.FollowedUserId == followedUserId)
            .ExecuteDeleteAsync(ct);
        return Result.Success();
    }
}
