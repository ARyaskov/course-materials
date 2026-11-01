using CourseFlow.Api.Common.Errors;
using CourseFlow.Api.Modules.Progress.Domain;
using FluentValidation;

namespace CourseFlow.Api.Modules.Progress;

public record LessonProgressDto(
    Guid LessonId,
    string Status,
    DateTimeOffset? CompletedAt,
    int? LastWatchedSeconds)
{
    public static LessonProgressDto FromDomain(LessonProgress p) =>
        new(p.LessonId, p.Status.ToString(), p.CompletedAt, p.LastWatchedSeconds);
}

public record CourseProgressDto(
    Guid CourseId,
    int TotalLessons,
    int CompletedLessons,
    double ProgressPercentage,
    bool IsCompleted,
    IReadOnlyList<LessonProgressDto> LessonProgresses);

public record UpdateVideoProgressRequest(int WatchedSeconds);

public static class ProgressErrors
{
    public static readonly Error NotFound =
        new("Progress.NotFound", "Progress record not found (are you enrolled in this course?)", ErrorType.NotFound);
}

public sealed class UpdateVideoProgressRequestValidator : AbstractValidator<UpdateVideoProgressRequest>
{
    public UpdateVideoProgressRequestValidator() =>
        RuleFor(x => x.WatchedSeconds).GreaterThanOrEqualTo(0).LessThanOrEqualTo(24 * 3600);
}
