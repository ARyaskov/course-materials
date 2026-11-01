using CourseFlow.Api.Common.Errors;
using CourseFlow.Api.Modules.Lessons.Domain;
using FluentValidation;

namespace CourseFlow.Api.Modules.Lessons;

public record AddLessonRequest(
    string Title,
    LessonType Type,
    string? Description = null,
    string? ContentUrl = null,
    string? TextContent = null,
    TimeSpan? Duration = null,
    bool IsFree = false);

public record UpdateLessonRequest(
    string Title,
    string? Description,
    string? ContentUrl,
    string? TextContent,
    TimeSpan? Duration,
    bool IsFree);

public record ReorderLessonsRequest(IReadOnlyList<Guid> OrderedLessonIds);

/// <summary>
/// DTO урока с контролем доступа к контенту: Preview не содержит ContentUrl/TextContent.
/// </summary>
public record LessonDto(
    Guid Id,
    Guid CourseId,
    string Title,
    string? Description,
    string Type,
    int OrderIndex,
    TimeSpan? Duration,
    bool IsFree,
    bool IsPreview,
    string? ContentUrl,
    string? TextContent)
{
    public static LessonDto Full(Lesson l) => new(
        l.Id, l.CourseId, l.Title, l.Description, l.Type.ToString(), l.OrderIndex,
        l.Duration, l.IsFree, IsPreview: false, l.ContentUrl, l.TextContent);

    public static LessonDto Preview(Lesson l) => new(
        l.Id, l.CourseId, l.Title, l.Description, l.Type.ToString(), l.OrderIndex,
        l.Duration, l.IsFree, IsPreview: true, ContentUrl: null, TextContent: null);
}

public static class LessonErrors
{
    public static Error NotFound(Guid id) =>
        new("Lesson.NotFound", $"Lesson '{id}' was not found", ErrorType.NotFound);

    public static readonly Error VideoRequiresContentUrl =
        new("Lesson.VideoRequiresContentUrl", "Video lesson requires ContentUrl", ErrorType.Validation);

    public static readonly Error UnknownLessonInOrder =
        new("Lesson.UnknownInOrder", "Ordered list contains a lesson that does not belong to the course", ErrorType.Validation);
}

public sealed class AddLessonRequestValidator : AbstractValidator<AddLessonRequest>
{
    public AddLessonRequestValidator()
    {
        RuleFor(x => x.Title).NotEmpty().MaximumLength(200);
        RuleFor(x => x.Type).IsInEnum();
        RuleFor(x => x.ContentUrl).MaximumLength(2000);
        RuleFor(x => x.ContentUrl).NotEmpty().When(x => x.Type == LessonType.Video)
            .WithMessage("Video lesson requires ContentUrl");
        RuleFor(x => x.Duration).GreaterThan(TimeSpan.Zero).When(x => x.Duration.HasValue);
    }
}

public sealed class UpdateLessonRequestValidator : AbstractValidator<UpdateLessonRequest>
{
    public UpdateLessonRequestValidator()
    {
        RuleFor(x => x.Title).NotEmpty().MaximumLength(200);
        RuleFor(x => x.ContentUrl).MaximumLength(2000);
        RuleFor(x => x.Duration).GreaterThan(TimeSpan.Zero).When(x => x.Duration.HasValue);
    }
}

public sealed class ReorderLessonsRequestValidator : AbstractValidator<ReorderLessonsRequest>
{
    public ReorderLessonsRequestValidator()
    {
        RuleFor(x => x.OrderedLessonIds).NotEmpty()
            .Must(ids => ids.Distinct().Count() == ids.Count).WithMessage("Lesson ids must be unique");
    }
}
