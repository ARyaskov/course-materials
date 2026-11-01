using CourseFlow.Api.Common.Errors;
using CourseFlow.Api.Modules.Courses.Domain;
using FluentValidation;

namespace CourseFlow.Api.Modules.Courses;

public record CreateCourseRequest(string Title, string Description, decimal Price);
public record UpdateCourseRequest(string Title, string Description, decimal Price);

/// <summary>
/// Публичное представление курса. Record с init-свойствами, а не позиционный:
/// Hot Chocolate дописывает OrderBy/Where ПОСЛЕ нашей проекции Select, и EF Core умеет
/// упростить обращение к члену только у object initializer (new CourseDto { Id = c.Id }),
/// но не у вызова конструктора позиционного record-а.
/// </summary>
public record CourseDto
{
    public required Guid Id { get; init; }
    public required string Title { get; init; }
    public required string Description { get; init; }
    public required decimal Price { get; init; }
    public required string Status { get; init; }
    public required Guid AuthorId { get; init; }
    public required DateTimeOffset CreatedAt { get; init; }
    public DateTimeOffset? PublishedAt { get; init; }

    // Используется только для уже загруженных в память сущностей.
    // В LINQ-выражения к БД этот метод подставлять нельзя — EF Core
    // не умеет транслировать вызовы методов в SQL (Глава 23.3).
    public static CourseDto FromDomain(Course course) => new()
    {
        Id = course.Id,
        Title = course.Title,
        Description = course.Description,
        Price = course.Price,
        Status = course.Status.ToString(),
        AuthorId = course.AuthorId,
        CreatedAt = course.CreatedAt,
        PublishedAt = course.PublishedAt
    };
}

public record PagedResult<T>(IReadOnlyList<T> Items, int Total, int Page, int PageSize)
{
    public bool HasNextPage => Page * PageSize < Total;
}

/// <summary>Отчёт по курсу для автора — SQL через Dapper (Глава 9.10).</summary>
public record CourseStatsDto(
    Guid CourseId,
    string Title,
    int Lessons,
    int ActiveEnrollments,
    int CompletedEnrollments,
    decimal Revenue);

public static class CourseErrors
{
    public static Error NotFound(Guid id) =>
        new("Course.NotFound", $"Course '{id}' was not found", ErrorType.NotFound);

    public static readonly Error NotAuthor =
        new("Course.NotAuthor", "Only the course author can perform this action", ErrorType.Forbidden);

    public static readonly Error AlreadyPublished =
        new("Course.AlreadyPublished", "Course is already published", ErrorType.Conflict);

    public static readonly Error NoLessonsToPublish =
        new("Course.NoLessons", "Cannot publish a course without lessons", ErrorType.Conflict);

    public static readonly Error CannotModifyPublished =
        new("Course.CannotModify", "Cannot modify a published course", ErrorType.Conflict);

    public static readonly Error Archived =
        new("Course.Archived", "Course is archived", ErrorType.Conflict);
}

public sealed class CreateCourseRequestValidator : AbstractValidator<CreateCourseRequest>
{
    public CreateCourseRequestValidator()
    {
        RuleFor(x => x.Title).NotEmpty().MaximumLength(200);
        RuleFor(x => x.Description).NotNull().MaximumLength(5000);
        RuleFor(x => x.Price).GreaterThanOrEqualTo(0).PrecisionScale(18, 2, ignoreTrailingZeros: true);
    }
}

public sealed class UpdateCourseRequestValidator : AbstractValidator<UpdateCourseRequest>
{
    public UpdateCourseRequestValidator()
    {
        RuleFor(x => x.Title).NotEmpty().MaximumLength(200);
        RuleFor(x => x.Description).NotNull().MaximumLength(5000);
        RuleFor(x => x.Price).GreaterThanOrEqualTo(0).PrecisionScale(18, 2, ignoreTrailingZeros: true);
    }
}
