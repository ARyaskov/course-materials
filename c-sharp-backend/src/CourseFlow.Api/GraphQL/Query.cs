using CourseFlow.Api.Common.Auth;
using CourseFlow.Api.Infrastructure.Data;
using CourseFlow.Api.Modules.Courses;
using CourseFlow.Api.Modules.Courses.Domain;
using CourseFlow.Api.Modules.Courses.Services;
using CourseFlow.Api.Modules.Enrollment;
using CourseFlow.Api.Modules.Enrollment.Domain;
using CourseFlow.Api.Modules.Lessons;
using CourseFlow.Api.Modules.Lessons.Services;
using CourseFlow.Api.Modules.Progress;
using CourseFlow.Api.Modules.Progress.Services;
using CourseFlow.Api.Modules.Users;
using CourseFlow.Api.Modules.Users.Services;
using HotChocolate.Authorization;
using HotChocolate.Data;
using HotChocolate.Types;
using Microsoft.EntityFrameworkCore;

namespace CourseFlow.Api.GraphQL;

/// <summary>
/// GraphQL Query (Глава 11, 23.9). Наружу отдаём DTO, а не доменные сущности: иначе
/// внутренние поля автоматически попадут в публичную схему при первом же изменении модели.
/// Бизнес-логика — в тех же сервисах, что и у REST: GraphQL здесь лишь другой транспорт.
/// </summary>
public class Query
{
    /// <summary>Каталог опубликованных курсов с фильтрацией и сортировкой на стороне БД.</summary>
    [UseFiltering, UseSorting]
    public IQueryable<CourseDto> GetPublishedCourses(AppDbContext db) =>
        db.Courses
            .AsNoTracking()
            .Where(c => c.Status == CourseStatus.Published)
            .Select(c => new CourseDto
            {
                Id = c.Id, Title = c.Title, Description = c.Description, Price = c.Price,
                Status = c.Status.ToString(), AuthorId = c.AuthorId,
                CreatedAt = c.CreatedAt, PublishedAt = c.PublishedAt
            });

    public async Task<CourseDto?> GetCourse(
        Guid id, CourseService service, ICurrentUser currentUser, CancellationToken ct)
    {
        var result = await service.GetByIdAsync(id, currentUser.UserId, ct);
        return result.IsSuccess ? result.Value : null;
    }

    /// <summary>Уроки курса с тем же контролем доступа, что и в REST (превью для не записанных).</summary>
    public async Task<IReadOnlyList<LessonDto>> GetCourseLessons(
        Guid courseId, LessonService service, ICurrentUser currentUser, CancellationToken ct)
    {
        var result = await service.GetCourseLessonsAsync(courseId, currentUser.UserId, ct);
        return result.IsSuccess ? result.Value : [];
    }

    [Authorize]
    public async Task<UserDto?> GetMe(UserService service, ICurrentUser currentUser, CancellationToken ct)
    {
        var result = await service.GetByIdAsync(currentUser.RequiredUserId(), ct);
        return result.IsSuccess ? result.Value : null;
    }

    [Authorize]
    public IQueryable<EnrollmentDto> GetMyEnrollments(AppDbContext db, ICurrentUser currentUser)
    {
        var userId = currentUser.RequiredUserId();
        return db.Enrollments
            .AsNoTracking()
            .Where(e => e.UserId == userId && e.Status != EnrollmentStatus.Revoked)
            .Join(db.Courses, e => e.CourseId, c => c.Id, (e, c) => new EnrollmentDto(
                e.Id, c.Id, c.Title, c.ThumbnailUrl, e.Status.ToString(), e.EnrolledAt, e.CompletedAt));
    }

    [Authorize]
    public async Task<CourseProgressDto?> GetMyProgress(
        Guid courseId, ProgressService service, ICurrentUser currentUser, CancellationToken ct)
    {
        var result = await service.GetCourseProgressAsync(courseId, currentUser.RequiredUserId(), ct);
        return result.IsSuccess ? result.Value : null;
    }
}
