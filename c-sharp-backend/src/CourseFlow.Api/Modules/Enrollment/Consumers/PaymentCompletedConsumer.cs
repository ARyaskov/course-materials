using CourseFlow.Api.Infrastructure.Data;
using CourseFlow.Api.Modules.Courses.Domain;
using CourseFlow.Api.Modules.Enrollment.Domain;
using CourseFlow.Contracts;
using MassTransit;
using Microsoft.EntityFrameworkCore;

namespace CourseFlow.Api.Modules.Enrollment.Consumers;

/// <summary>
/// PaymentCompleted → Enrollment (Глава 23.5). Consumer идемпотентен: RabbitMQ гарантирует
/// доставку "хотя бы раз", поэтому повтор сообщения — штатная ситуация, а не ошибка.
/// </summary>
public sealed class PaymentCompletedConsumer(
    AppDbContext db,
    IPublishEndpoint publishEndpoint,
    ILogger<PaymentCompletedConsumer> logger) : IConsumer<PaymentCompleted>
{
    public async Task Consume(ConsumeContext<PaymentCompleted> context)
    {
        var msg = context.Message;
        var ct = context.CancellationToken;

        // Идемпотентность: проверяем по PaymentId
        var alreadyEnrolled = await db.Enrollments.AnyAsync(e => e.PaymentId == msg.PaymentId, ct);
        if (alreadyEnrolled)
        {
            logger.LogWarning("Duplicate PaymentCompleted {PaymentId} — enrollment already exists", msg.PaymentId);
            return;
        }

        // Гонка двух платежей за один курс: первый уже создал запись — второй просто не дублирует её
        var activeEnrollment = await db.Enrollments.AnyAsync(
            e => e.UserId == msg.UserId && e.CourseId == msg.CourseId && e.Status != EnrollmentStatus.Revoked, ct);
        if (activeEnrollment)
        {
            logger.LogWarning("User {UserId} already has an enrollment in course {CourseId}; payment {PaymentId} skipped",
                msg.UserId, msg.CourseId, msg.PaymentId);
            return;
        }

        // Проверяем, что курс существует и опубликован
        var courseExists = await db.Courses.AnyAsync(
            c => c.Id == msg.CourseId && c.Status == CourseStatus.Published, ct);

        if (!courseExists)
        {
            logger.LogError("Course {CourseId} not found or not published for payment {PaymentId}",
                msg.CourseId, msg.PaymentId);
            // Выбрасываем — после retry сообщение уйдёт в _error-очередь для ручного разбора
            throw new InvalidOperationException($"Course {msg.CourseId} not available");
        }

        var enrollment = Domain.Enrollment.Create(msg.CourseId, msg.UserId, msg.PaymentId);
        db.Enrollments.Add(enrollment);

        // Публикуем событие через Outbox — атомарно с созданием Enrollment
        await publishEndpoint.Publish(new EnrollmentCreated(
            EnrollmentId: enrollment.Id,
            CourseId: msg.CourseId,
            UserId: msg.UserId,
            EnrolledAt: enrollment.EnrolledAt), ct);

        await db.SaveChangesAsync(ct);

        logger.LogInformation(
            "Enrollment {EnrollmentId} created for user {UserId} in course {CourseId}",
            enrollment.Id, msg.UserId, msg.CourseId);
    }
}

/// <summary>CourseCompleted → Enrollment.Complete(). Идемпотентно за счёт проверки статуса в домене.</summary>
public sealed class CourseCompletedEnrollmentConsumer(
    AppDbContext db,
    ILogger<CourseCompletedEnrollmentConsumer> logger) : IConsumer<CourseCompleted>
{
    public async Task Consume(ConsumeContext<CourseCompleted> context)
    {
        var msg = context.Message;

        var enrollment = await db.Enrollments
            .FirstOrDefaultAsync(e => e.Id == msg.EnrollmentId, context.CancellationToken);

        if (enrollment is null)
        {
            logger.LogWarning("CourseCompleted for unknown enrollment {EnrollmentId}", msg.EnrollmentId);
            return;
        }

        enrollment.Complete();
        await db.SaveChangesAsync(context.CancellationToken);
    }
}
