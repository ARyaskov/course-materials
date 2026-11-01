namespace CourseFlow.Api.Modules.Enrollment.Domain;

public enum EnrollmentStatus { Active, Completed, Revoked }

/// <summary>Запись студента на курс (Глава 23.5). Создаётся consumer-ом PaymentCompleted.</summary>
public class Enrollment
{
    public Guid Id { get; private set; } = Guid.CreateVersion7();
    public Guid CourseId { get; private set; }
    public Guid UserId { get; private set; }
    public Guid? PaymentId { get; private set; }
    public EnrollmentStatus Status { get; private set; } = EnrollmentStatus.Active;
    public DateTimeOffset EnrolledAt { get; private set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? CompletedAt { get; private set; }

    private Enrollment() { } // EF Core

    public static Enrollment Create(Guid courseId, Guid userId, Guid? paymentId = null) => new()
    {
        CourseId = courseId,
        UserId = userId,
        PaymentId = paymentId
    };

    public void Complete()
    {
        if (Status == EnrollmentStatus.Completed) return; // идемпотентно: событие может прийти повторно

        if (Status != EnrollmentStatus.Active)
            throw new InvalidOperationException("Only active enrollments can be completed");

        Status = EnrollmentStatus.Completed;
        CompletedAt = DateTimeOffset.UtcNow;
    }

    public void Revoke() => Status = EnrollmentStatus.Revoked;

    public bool IsActive() => Status == EnrollmentStatus.Active;
}
