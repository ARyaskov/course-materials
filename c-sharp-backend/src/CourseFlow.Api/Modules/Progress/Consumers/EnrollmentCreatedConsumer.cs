using CourseFlow.Api.Infrastructure.Data;
using CourseFlow.Api.Modules.Progress.Domain;
using CourseFlow.Contracts;
using MassTransit;
using Microsoft.EntityFrameworkCore;

namespace CourseFlow.Api.Modules.Progress.Consumers;

/// <summary>EnrollmentCreated → начальный прогресс по каждому уроку курса (Глава 23.6).</summary>
public sealed class EnrollmentCreatedConsumer(
    AppDbContext db,
    ILogger<EnrollmentCreatedConsumer> logger) : IConsumer<EnrollmentCreated>
{
    public async Task Consume(ConsumeContext<EnrollmentCreated> context)
    {
        var msg = context.Message;
        var ct = context.CancellationToken;

        // Идемпотентность: проверяем, существует ли уже прогресс
        var alreadyInitialized = await db.LessonProgresses.AnyAsync(p => p.EnrollmentId == msg.EnrollmentId, ct);
        if (alreadyInitialized)
        {
            logger.LogWarning("Progress already initialized for enrollment {EnrollmentId}", msg.EnrollmentId);
            return;
        }

        var lessonIds = await db.Lessons
            .Where(l => l.CourseId == msg.CourseId)
            .Select(l => l.Id)
            .ToListAsync(ct);

        var progresses = lessonIds.Select(lessonId =>
            LessonProgress.Create(msg.EnrollmentId, lessonId, msg.UserId, msg.CourseId));

        db.LessonProgresses.AddRange(progresses);
        await db.SaveChangesAsync(ct);

        logger.LogInformation(
            "Initialized progress for {Count} lessons, enrollment {EnrollmentId}",
            lessonIds.Count, msg.EnrollmentId);
    }
}
