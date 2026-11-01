using CourseFlow.Api.Infrastructure.Data;
using CourseFlow.Api.Modules.Enrollment.Domain;
using Microsoft.EntityFrameworkCore;

namespace CourseFlow.Api.Modules.Enrollment.Services;

public sealed class EnrollmentService(AppDbContext db)
{
    public async Task<IReadOnlyList<EnrollmentDto>> GetUserEnrollmentsAsync(Guid userId, CancellationToken ct) =>
        await db.Enrollments
            .AsNoTracking()
            .Where(e => e.UserId == userId && e.Status != EnrollmentStatus.Revoked)
            // Сортировка ДО проекции: OrderBy по свойству сконструированного DTO EF Core не транслирует
            .OrderByDescending(e => e.EnrolledAt)
            // Join с курсами через LINQ: модуль читает чужие данные только для проекции, не изменяет их
            .Join(db.Courses,
                e => e.CourseId,
                c => c.Id,
                (e, c) => new EnrollmentDto(
                    e.Id, c.Id, c.Title, c.ThumbnailUrl,
                    e.Status.ToString(), e.EnrolledAt, e.CompletedAt))
            .ToListAsync(ct);

    public async Task<bool> IsEnrolledAsync(Guid userId, Guid courseId, CancellationToken ct) =>
        await db.Enrollments.AnyAsync(
            e => e.UserId == userId
                 && e.CourseId == courseId
                 && e.Status == EnrollmentStatus.Active,
            ct);
}
