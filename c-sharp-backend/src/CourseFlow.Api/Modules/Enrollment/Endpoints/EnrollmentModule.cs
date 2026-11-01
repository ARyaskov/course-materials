using CourseFlow.Api.Common.Auth;
using CourseFlow.Api.Modules.Enrollment.Services;

namespace CourseFlow.Api.Modules.Enrollment.Endpoints;

public static class EnrollmentModule
{
    public static IServiceCollection AddEnrollmentModule(this IServiceCollection services)
    {
        services.AddScoped<EnrollmentService>();
        return services;
    }

    public static IEndpointRouteBuilder MapEnrollments(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/v1/enrollments")
            .RequireAuthorization()
            .WithTags("Enrollment");

        // Мои зачисления
        group.MapGet("/", GetMyEnrollmentsAsync).Produces<IReadOnlyList<EnrollmentDto>>();

        // Проверка доступа к курсу
        group.MapGet("/check/{courseId:guid}", CheckEnrollmentAsync).Produces<EnrollmentCheckDto>();

        return app;
    }

    private static async Task<IResult> GetMyEnrollmentsAsync(
        EnrollmentService service, ICurrentUser currentUser, CancellationToken ct)
    {
        var enrollments = await service.GetUserEnrollmentsAsync(currentUser.RequiredUserId(), ct);
        return Results.Ok(enrollments);
    }

    private static async Task<IResult> CheckEnrollmentAsync(
        Guid courseId, EnrollmentService service, ICurrentUser currentUser, CancellationToken ct)
    {
        var isEnrolled = await service.IsEnrolledAsync(currentUser.RequiredUserId(), courseId, ct);
        return Results.Ok(new EnrollmentCheckDto(courseId, isEnrolled));
    }
}
