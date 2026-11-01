using CourseFlow.Api.Common.Auth;
using CourseFlow.Api.Common.Errors;
using CourseFlow.Api.Common.Validation;
using CourseFlow.Api.Modules.Courses.Services;

namespace CourseFlow.Api.Modules.Courses.Endpoints;

public static class CoursesModule
{
    public static IServiceCollection AddCoursesModule(this IServiceCollection services)
    {
        services.AddScoped<CourseService>();
        return services;
    }

    public static IEndpointRouteBuilder MapCourses(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/v1/courses").WithTags("Courses");

        // Публичные endpoints
        group.MapGet("/", GetPublishedAsync).Produces<PagedResult<CourseDto>>();
        group.MapGet("/{id:guid}", GetByIdAsync)
            .Produces<CourseDto>()
            .ProducesProblem(StatusCodes.Status404NotFound);

        // Защищённые endpoints: политика "Instructor" = роли Instructor или Admin (Глава 13.7)
        group.MapGet("/mine", GetMineAsync)
            .RequireAuthorization("Instructor")
            .Produces<IReadOnlyList<CourseDto>>();

        group.MapPost("/", CreateAsync)
            .RequireAuthorization("Instructor")
            .WithValidation<CreateCourseRequest>()
            .Produces<CourseDto>(StatusCodes.Status201Created);

        group.MapPut("/{id:guid}", UpdateAsync)
            .RequireAuthorization("Instructor")
            .WithValidation<UpdateCourseRequest>()
            .Produces<CourseDto>()
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict);

        group.MapPost("/{id:guid}/publish", PublishAsync)
            .RequireAuthorization("Instructor")
            .Produces<CourseDto>()
            .ProducesProblem(StatusCodes.Status409Conflict);

        group.MapGet("/{id:guid}/stats", GetStatsAsync)
            .RequireAuthorization("Instructor")
            .Produces<CourseStatsDto>()
            .ProducesProblem(StatusCodes.Status404NotFound);

        return app;
    }

    private static async Task<IResult> GetPublishedAsync(
        CourseService service,
        CancellationToken ct,
        int page = 1,
        int pageSize = 20,
        string? search = null)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 100);

        var result = await service.GetPublishedAsync(page, pageSize, search, ct);
        return Results.Ok(result);
    }

    private static async Task<IResult> GetByIdAsync(
        Guid id, CourseService service, ICurrentUser currentUser, CancellationToken ct)
    {
        // Endpoint публичный: для анонима UserId == null,
        // и сервис вернёт NotFound для неопубликованного курса
        var result = await service.GetByIdAsync(id, currentUser.UserId, ct);
        return result.ToHttpResult(Results.Ok);
    }

    private static async Task<IResult> GetMineAsync(
        CourseService service, ICurrentUser currentUser, CancellationToken ct) =>
        Results.Ok(await service.GetMineAsync(currentUser.RequiredUserId(), ct));

    private static async Task<IResult> CreateAsync(
        CreateCourseRequest request, CourseService service, ICurrentUser currentUser, CancellationToken ct)
    {
        // RequireAuthorization гарантирует пользователя — RequiredUserId здесь безопасен
        var course = await service.CreateAsync(request, currentUser.RequiredUserId(), ct);
        return Results.Created($"/api/v1/courses/{course.Id}", course);
    }

    private static async Task<IResult> UpdateAsync(
        Guid id, UpdateCourseRequest request, CourseService service, ICurrentUser currentUser, CancellationToken ct)
    {
        var result = await service.UpdateAsync(id, request, currentUser.RequiredUserId(), ct);
        return result.ToHttpResult(Results.Ok);
    }

    private static async Task<IResult> PublishAsync(
        Guid id, CourseService service, ICurrentUser currentUser, CancellationToken ct)
    {
        var result = await service.PublishAsync(id, currentUser.RequiredUserId(), ct);
        return result.ToHttpResult(Results.Ok);
    }

    private static async Task<IResult> GetStatsAsync(
        Guid id, CourseService service, ICurrentUser currentUser, CancellationToken ct)
    {
        var result = await service.GetStatsAsync(id, currentUser.RequiredUserId(), ct);
        return result.ToHttpResult(Results.Ok);
    }
}
