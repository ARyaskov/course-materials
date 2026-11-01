using CourseFlow.Api.Common.Errors;
using CourseFlow.Api.Infrastructure.Data;
using CourseFlow.Api.Modules.Progress.Domain;
using CourseFlow.Contracts;
using MassTransit;
using Microsoft.EntityFrameworkCore;

namespace CourseFlow.Api.Modules.Progress.Services;

public sealed class ProgressService(
    AppDbContext db,
    IPublishEndpoint publishEndpoint,
    ILogger<ProgressService> logger)
{
    public async Task<Result> MarkLessonCompletedAsync(Guid lessonId, Guid userId, CancellationToken ct)
    {
        var progress = await db.LessonProgresses
            .FirstOrDefaultAsync(p => p.LessonId == lessonId && p.UserId == userId, ct);

        if (progress is null)
            return ProgressErrors.NotFound;

        if (progress.Status == ProgressStatus.Completed)
            return Result.Success(); // идемпотентно

        progress.MarkCompleted();

        // Последний урок закрыт — курс пройден. Событие уходит через Outbox
        // в одной транзакции с отметкой урока (Глава 17.5)
        var remaining = await db.LessonProgresses.CountAsync(
            p => p.EnrollmentId == progress.EnrollmentId
                 && p.Id != progress.Id
                 && p.Status != ProgressStatus.Completed, ct);

        if (remaining == 0)
        {
            await publishEndpoint.Publish(new CourseCompleted(
                EnrollmentId: progress.EnrollmentId,
                CourseId: progress.CourseId,
                UserId: userId,
                CompletedAt: progress.CompletedAt!.Value), ct);

            logger.LogInformation("User {UserId} completed course {CourseId}", userId, progress.CourseId);
        }

        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    public async Task<Result<CourseProgressDto>> GetCourseProgressAsync(Guid courseId, Guid userId, CancellationToken ct)
    {
        var progresses = await db.LessonProgresses
            .AsNoTracking()
            .Where(p => p.CourseId == courseId && p.UserId == userId)
            .ToListAsync(ct);

        if (progresses.Count == 0)
            return ProgressErrors.NotFound;

        var total = progresses.Count;
        var completed = progresses.Count(p => p.Status == ProgressStatus.Completed);
        var percentage = total > 0 ? (double)completed / total * 100 : 0;

        return Result.Success(new CourseProgressDto(
            CourseId: courseId,
            TotalLessons: total,
            CompletedLessons: completed,
            ProgressPercentage: Math.Round(percentage, 1),
            IsCompleted: completed == total && total > 0,
            LessonProgresses: progresses.Select(LessonProgressDto.FromDomain).ToList()));
    }

    public async Task<Result> UpdateVideoProgressAsync(Guid lessonId, Guid userId, int watchedSeconds, CancellationToken ct)
    {
        var progress = await db.LessonProgresses
            .FirstOrDefaultAsync(p => p.LessonId == lessonId && p.UserId == userId, ct);

        if (progress is null)
            return ProgressErrors.NotFound;

        progress.UpdateVideoProgress(watchedSeconds);
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }
}
