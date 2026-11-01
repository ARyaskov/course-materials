using CourseFlow.Api.Common.Auth;
using CourseFlow.Api.Modules.Courses.Domain;
using CourseFlow.Api.Modules.Lessons.Domain;
using CourseFlow.Api.Modules.Users.Domain;
using Microsoft.EntityFrameworkCore;

namespace CourseFlow.Api.Infrastructure.Data;

/// <summary>
/// Демо-данные для локальной разработки: admin, instructor и опубликованный курс.
/// Включается флагом Seed:Enabled и никогда не выполняется в production.
/// </summary>
public static class DbSeeder
{
    public const string AdminEmail = "admin@courseflow.io";
    public const string InstructorEmail = "instructor@courseflow.io";
    public const string DemoPassword = "Passw0rd!";

    public static async Task SeedAsync(this WebApplication app, CancellationToken ct = default)
    {
        await using var scope = app.Services.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var hasher = scope.ServiceProvider.GetRequiredService<IPasswordHasher>();
        var logger = scope.ServiceProvider.GetRequiredService<ILogger<AppDbContext>>();

        if (await db.Users.AnyAsync(ct))
            return;

        var admin = User.Create(AdminEmail, hasher.Hash(DemoPassword), "Ada", "Admin");
        admin.SetRole(UserRole.Admin);

        var instructor = User.Create(InstructorEmail, hasher.Hash(DemoPassword), "Ian", "Instructor");
        instructor.SetRole(UserRole.Instructor);

        db.Users.AddRange(admin, instructor);

        var course = Course.Create(
            "Backend на C# и .NET 11",
            "Демо-курс CourseFlow: Minimal APIs, EF Core, messaging и всё, что между ними.",
            instructor.Id,
            49.99m);

        var intro = course.AddLesson("Введение", LessonType.Text);
        intro.UpdateContent("Что такое CourseFlow", null, "CourseFlow — backend платформы онлайн-курсов.", null);
        intro.MakeFree();

        var minimal = course.AddLesson("Minimal APIs", LessonType.Video);
        minimal.UpdateContent("Первый endpoint", "https://videos.courseflow.io/minimal-apis.mp4", null, TimeSpan.FromMinutes(18));

        var ef = course.AddLesson("EF Core и PostgreSQL", LessonType.Video);
        ef.UpdateContent("Работа с базой данных", "https://videos.courseflow.io/ef-core.mp4", null, TimeSpan.FromMinutes(24));

        course.Publish();
        db.Courses.Add(course);

        await db.SaveChangesAsync(ct);

        logger.LogInformation("Seeded demo data: {Admin}, {Instructor}, course {CourseId}",
            AdminEmail, InstructorEmail, course.Id);
    }
}
