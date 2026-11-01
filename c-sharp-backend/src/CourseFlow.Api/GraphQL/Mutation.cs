using CourseFlow.Api.Common.Auth;
using CourseFlow.Api.Modules.Courses;
using CourseFlow.Api.Modules.Courses.Services;
using CourseFlow.Api.Modules.Progress.Services;
using HotChocolate.Authorization;

namespace CourseFlow.Api.GraphQL;

public record CreateCourseInput(string Title, string Description, decimal Price)
{
    public CreateCourseRequest ToRequest() => new(Title, Description, Price);
}

/// <summary>Ошибка в payload (Глава 11.5): бизнес-ошибки — часть схемы, а не GraphQL errors.</summary>
public record UserError(string Code, string Message);

public record CoursePayload(CourseDto? Course, IReadOnlyList<UserError> Errors);
public record MarkLessonCompletedPayload(bool Success, IReadOnlyList<UserError> Errors);

/// <summary>
/// GraphQL Mutation (Глава 11.5, 23.9). Payload pattern: клиент всегда получает объект
/// с данными и списком ошибок, а не исключение верхнего уровня.
/// </summary>
public class Mutation
{
    [Authorize(Policy = "Instructor")]
    public async Task<CoursePayload> CreateCourse(
        CreateCourseInput input, CourseService service, ICurrentUser currentUser, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(input.Title))
            return new CoursePayload(null, [new UserError("Course.TitleRequired", "Title is required")]);
        if (input.Price < 0)
            return new CoursePayload(null, [new UserError("Course.NegativePrice", "Price cannot be negative")]);

        var course = await service.CreateAsync(input.ToRequest(), currentUser.RequiredUserId(), ct);
        return new CoursePayload(course, []);
    }

    [Authorize(Policy = "Instructor")]
    public async Task<CoursePayload> PublishCourse(
        Guid courseId, CourseService service, ICurrentUser currentUser, CancellationToken ct)
    {
        var result = await service.PublishAsync(courseId, currentUser.RequiredUserId(), ct);
        return result.IsSuccess
            ? new CoursePayload(result.Value, [])
            : new CoursePayload(null, [ToUserError(result.Error)]);
    }

    [Authorize]
    public async Task<MarkLessonCompletedPayload> MarkLessonCompleted(
        Guid lessonId, ProgressService service, ICurrentUser currentUser, CancellationToken ct)
    {
        var result = await service.MarkLessonCompletedAsync(lessonId, currentUser.RequiredUserId(), ct);
        return result.IsSuccess
            ? new MarkLessonCompletedPayload(true, [])
            : new MarkLessonCompletedPayload(false, [ToUserError(result.Error)]);
    }

    private static UserError ToUserError(Common.Errors.Error error) => new(error.Code, error.Description);
}
