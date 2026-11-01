using CourseFlow.Api.Common.Auth;
using CourseFlow.Api.Common.Errors;
using CourseFlow.Api.Common.Validation;
using CourseFlow.Api.Modules.Lessons.Services;

namespace CourseFlow.Api.Modules.Lessons.Endpoints;

public static class LessonsModule
{
    public static IServiceCollection AddLessonsModule(this IServiceCollection services)
    {
        services.AddScoped<LessonService>();
        return services;
    }

    public static IEndpointRouteBuilder MapLessons(this IEndpointRouteBuilder app)
    {
        // Вложенный ресурс: урок не существует вне курса (Глава 6.3)
        var group = app.MapGroup("/api/v1/courses/{courseId:guid}/lessons").WithTags("Lessons");

        group.MapGet("/", GetCourseLessonsAsync).Produces<IReadOnlyList<LessonDto>>();
        group.MapGet("/{lessonId:guid}", GetLessonAsync)
            .Produces<LessonDto>()
            .ProducesProblem(StatusCodes.Status404NotFound);

        group.MapPost("/", AddLessonAsync)
            .RequireAuthorization("Instructor")
            .WithValidation<AddLessonRequest>()
            .Produces<LessonDto>(StatusCodes.Status201Created);

        group.MapPut("/reorder", ReorderLessonsAsync)
            .RequireAuthorization("Instructor")
            .WithValidation<ReorderLessonsRequest>()
            .Produces(StatusCodes.Status204NoContent);

        group.MapPut("/{lessonId:guid}", UpdateLessonAsync)
            .RequireAuthorization("Instructor")
            .WithValidation<UpdateLessonRequest>()
            .Produces<LessonDto>();

        group.MapDelete("/{lessonId:guid}", DeleteLessonAsync)
            .RequireAuthorization("Instructor")
            .Produces(StatusCodes.Status204NoContent);

        return app;
    }

    private static async Task<IResult> GetCourseLessonsAsync(
        Guid courseId, LessonService service, ICurrentUser currentUser, CancellationToken ct)
    {
        // Endpoint публичный: currentUser.UserId равен null для анонима,
        // и сервис сам решает, отдавать полный контент или превью.
        var result = await service.GetCourseLessonsAsync(courseId, currentUser.UserId, ct);
        return result.ToHttpResult(Results.Ok);
    }

    private static async Task<IResult> GetLessonAsync(
        Guid courseId, Guid lessonId, LessonService service, ICurrentUser currentUser, CancellationToken ct)
    {
        var result = await service.GetLessonAsync(courseId, lessonId, currentUser.UserId, ct);
        return result.ToHttpResult(Results.Ok);
    }

    private static async Task<IResult> AddLessonAsync(
        Guid courseId, AddLessonRequest request, LessonService service, ICurrentUser currentUser, CancellationToken ct)
    {
        var result = await service.AddLessonAsync(courseId, request, currentUser.RequiredUserId(), ct);
        return result.ToHttpResult(l => Results.Created($"/api/v1/courses/{courseId}/lessons/{l.Id}", l));
    }

    private static async Task<IResult> UpdateLessonAsync(
        Guid courseId, Guid lessonId, UpdateLessonRequest request, LessonService service,
        ICurrentUser currentUser, CancellationToken ct)
    {
        var result = await service.UpdateLessonAsync(courseId, lessonId, request, currentUser.RequiredUserId(), ct);
        return result.ToHttpResult(Results.Ok);
    }

    private static async Task<IResult> DeleteLessonAsync(
        Guid courseId, Guid lessonId, LessonService service, ICurrentUser currentUser, CancellationToken ct)
    {
        var result = await service.DeleteLessonAsync(courseId, lessonId, currentUser.RequiredUserId(), ct);
        return result.ToHttpResult(Results.NoContent());
    }

    private static async Task<IResult> ReorderLessonsAsync(
        Guid courseId, ReorderLessonsRequest request, LessonService service,
        ICurrentUser currentUser, CancellationToken ct)
    {
        var result = await service.ReorderLessonsAsync(courseId, request.OrderedLessonIds, currentUser.RequiredUserId(), ct);
        return result.ToHttpResult(Results.NoContent());
    }
}
