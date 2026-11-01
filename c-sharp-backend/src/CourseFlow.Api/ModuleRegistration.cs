using CourseFlow.Api.Modules.Billing.Endpoints;
using CourseFlow.Api.Modules.Courses.Endpoints;
using CourseFlow.Api.Modules.Enrollment.Endpoints;
using CourseFlow.Api.Modules.Lessons.Endpoints;
using CourseFlow.Api.Modules.Notifications.Endpoints;
using CourseFlow.Api.Modules.Progress.Endpoints;
using CourseFlow.Api.Modules.Users.Endpoints;

namespace CourseFlow.Api;

/// <summary>
/// Композиция модулей (Глава 8 "Modular Monolith"): Program.cs знает только про AddModules/MapModules,
/// а состав каждого модуля — его внутреннее дело.
/// </summary>
public static class ModuleRegistration
{
    public static IServiceCollection AddModules(this IServiceCollection services) =>
        services
            .AddUsersModule()
            .AddCoursesModule()
            .AddLessonsModule()
            .AddEnrollmentModule()
            .AddProgressModule()
            .AddBillingModule()
            .AddNotificationsModule();

    public static IEndpointRouteBuilder MapModules(this IEndpointRouteBuilder app)
    {
        app.MapUsers();
        app.MapCourses();
        app.MapLessons();
        app.MapEnrollments();
        app.MapProgress();
        app.MapBilling();
        app.MapNotifications();
        return app;
    }
}
