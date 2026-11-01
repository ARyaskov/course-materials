namespace CourseFlow.Api.Modules.Progress.Domain;

public enum ProgressStatus { NotStarted, InProgress, Completed }

/// <summary>Прогресс студента по одному уроку (Глава 23.6). Создаётся при EnrollmentCreated.</summary>
public class LessonProgress
{
    public Guid Id { get; private set; } = Guid.CreateVersion7();
    public Guid EnrollmentId { get; private set; }
    public Guid LessonId { get; private set; }
    public Guid UserId { get; private set; }
    public Guid CourseId { get; private set; }
    public ProgressStatus Status { get; private set; } = ProgressStatus.NotStarted;
    public DateTimeOffset? CompletedAt { get; private set; }
    public int? LastWatchedSeconds { get; private set; }

    private LessonProgress() { } // EF Core

    public static LessonProgress Create(Guid enrollmentId, Guid lessonId, Guid userId, Guid courseId) => new()
    {
        EnrollmentId = enrollmentId,
        LessonId = lessonId,
        UserId = userId,
        CourseId = courseId
    };

    public void MarkCompleted()
    {
        if (Status == ProgressStatus.Completed) return; // идемпотентно

        Status = ProgressStatus.Completed;
        CompletedAt = DateTimeOffset.UtcNow;
    }

    public void UpdateVideoProgress(int watchedSeconds)
    {
        if (watchedSeconds < 0) throw new ArgumentOutOfRangeException(nameof(watchedSeconds));

        LastWatchedSeconds = watchedSeconds;
        if (Status == ProgressStatus.NotStarted)
            Status = ProgressStatus.InProgress;
    }
}
