using CourseFlow.Api.Common.Auth;
using CourseFlow.Api.Common.Errors;
using CourseFlow.Api.Common.Validation;
using CourseFlow.Api.Modules.Progress.Services;

namespace CourseFlow.Api.Modules.Progress.Endpoints;

public static class ProgressModule
{
    public static IServiceCollection AddProgressModule(this IServiceCollection services)
    {
        services.AddScoped<ProgressService>();
        return services;
    }

    public static IEndpointRouteBuilder MapProgress(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/v1/progress")
            .RequireAuthorization()
            .WithTags("Progress");

        group.MapGet("/{courseId:guid}", GetCourseProgressAsync)
            .Produces<CourseProgressDto>()
            .ProducesProblem(StatusCodes.Status404NotFound);

        group.MapPost("/lessons/{lessonId:guid}/complete", MarkLessonCompletedAsync)
            .Produces(StatusCodes.Status204NoContent);

        group.MapPut("/lessons/{lessonId:guid}/video", UpdateVideoProgressAsync)
            .WithValidation<UpdateVideoProgressRequest>()
            .Produces(StatusCodes.Status204NoContent);

        return app;
    }

    private static async Task<IResult> GetCourseProgressAsync(
        Guid courseId, ProgressService service, ICurrentUser currentUser, CancellationToken ct)
    {
        var result = await service.GetCourseProgressAsync(courseId, currentUser.RequiredUserId(), ct);
        return result.ToHttpResult(Results.Ok);
    }

    private static async Task<IResult> MarkLessonCompletedAsync(
        Guid lessonId, ProgressService service, ICurrentUser currentUser, CancellationToken ct)
    {
        var result = await service.MarkLessonCompletedAsync(lessonId, currentUser.RequiredUserId(), ct);
        return result.ToHttpResult(Results.NoContent());
    }

    private static async Task<IResult> UpdateVideoProgressAsync(
        Guid lessonId, UpdateVideoProgressRequest request, ProgressService service,
        ICurrentUser currentUser, CancellationToken ct)
    {
        var result = await service.UpdateVideoProgressAsync(lessonId, currentUser.RequiredUserId(), request.WatchedSeconds, ct);
        return result.ToHttpResult(Results.NoContent());
    }
}
