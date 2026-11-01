namespace CourseFlow.Api.Modules.Enrollment;

public record EnrollmentDto(
    Guid Id,
    Guid CourseId,
    string CourseTitle,
    string? ThumbnailUrl,
    string Status,
    DateTimeOffset EnrolledAt,
    DateTimeOffset? CompletedAt);

public record EnrollmentCheckDto(Guid CourseId, bool IsEnrolled);
