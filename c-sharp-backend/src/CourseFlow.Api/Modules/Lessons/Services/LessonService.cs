using CourseFlow.Api.Common.Errors;
using CourseFlow.Api.Infrastructure.Data;
using CourseFlow.Api.Modules.Courses;
using CourseFlow.Api.Modules.Courses.Domain;
using CourseFlow.Api.Modules.Enrollment.Domain;
using CourseFlow.Api.Modules.Lessons.Domain;
using Microsoft.EntityFrameworkCore;

namespace CourseFlow.Api.Modules.Lessons.Services;

/// <summary>Модуль Lessons (Глава 23.4): контроль доступа к контенту на уровне DTO.</summary>
public sealed class LessonService(AppDbContext db, ILogger<LessonService> logger)
{
    public async Task<Result<LessonDto>> AddLessonAsync(
        Guid courseId, AddLessonRequest request, Guid instructorId, CancellationToken ct)
    {
        var course = await db.Courses
            .Include(c => c.Lessons)
            .FirstOrDefaultAsync(c => c.Id == courseId, ct);

        if (course is null)
            return CourseErrors.NotFound(courseId);

        if (course.AuthorId != instructorId)
            return CourseErrors.NotAuthor;

        if (course.Status == CourseStatus.Archived)
            return CourseErrors.Archived;

        // Порядковый номер вычисляет агрегат Course: max(order) + 1
        var lesson = course.AddLesson(request.Title, request.Type);

        if (request.ContentUrl is not null || request.TextContent is not null || request.Description is not null)
            lesson.UpdateContent(request.Description, request.ContentUrl, request.TextContent, request.Duration);

        if (request.IsFree)
            lesson.MakeFree();

        await db.SaveChangesAsync(ct);

        logger.LogInformation("Lesson {LessonId} added to course {CourseId}", lesson.Id, courseId);

        return Result.Success(LessonDto.Full(lesson));
    }

    public async Task<Result<LessonDto>> UpdateLessonAsync(
        Guid courseId, Guid lessonId, UpdateLessonRequest request, Guid instructorId, CancellationToken ct)
    {
        var course = await db.Courses
            .Include(c => c.Lessons)
            .FirstOrDefaultAsync(c => c.Id == courseId, ct);

        if (course is null)
            return CourseErrors.NotFound(courseId);

        if (course.AuthorId != instructorId)
            return CourseErrors.NotAuthor;

        var lesson = course.Lessons.FirstOrDefault(l => l.Id == lessonId);
        if (lesson is null)
            return LessonErrors.NotFound(lessonId);

        if (lesson.Type == LessonType.Video && string.IsNullOrEmpty(request.ContentUrl))
            return LessonErrors.VideoRequiresContentUrl;

        lesson.Rename(request.Title);
        lesson.UpdateContent(request.Description, request.ContentUrl, request.TextContent, request.Duration);
        if (request.IsFree) lesson.MakeFree(); else lesson.MakePaid();

        await db.SaveChangesAsync(ct);
        return Result.Success(LessonDto.Full(lesson));
    }

    public async Task<Result> DeleteLessonAsync(
        Guid courseId, Guid lessonId, Guid instructorId, CancellationToken ct)
    {
        var course = await db.Courses
            .Include(c => c.Lessons)
            .FirstOrDefaultAsync(c => c.Id == courseId, ct);

        if (course is null)
            return CourseErrors.NotFound(courseId);

        if (course.AuthorId != instructorId)
            return CourseErrors.NotAuthor;

        if (course.Status == CourseStatus.Published)
            return CourseErrors.CannotModifyPublished;

        var lesson = course.Lessons.FirstOrDefault(l => l.Id == lessonId);
        if (lesson is null)
            return LessonErrors.NotFound(lessonId);

        course.RemoveLesson(lesson);
        db.Lessons.Remove(lesson);
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    public async Task<Result> ReorderLessonsAsync(
        Guid courseId, IReadOnlyList<Guid> orderedLessonIds, Guid instructorId, CancellationToken ct)
    {
        var course = await db.Courses
            .Include(c => c.Lessons)
            .FirstOrDefaultAsync(c => c.Id == courseId, ct);

        if (course is null)
            return CourseErrors.NotFound(courseId);

        if (course.AuthorId != instructorId)
            return CourseErrors.NotAuthor;

        var known = course.Lessons.Select(l => l.Id).ToHashSet();
        if (orderedLessonIds.Any(id => !known.Contains(id)))
            return LessonErrors.UnknownLessonInOrder;

        for (var i = 0; i < orderedLessonIds.Count; i++)
        {
            var lesson = course.Lessons.First(l => l.Id == orderedLessonIds[i]);
            lesson.Reorder(i + 1);
        }

        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    public async Task<Result<IReadOnlyList<LessonDto>>> GetCourseLessonsAsync(
        Guid courseId, Guid? userId, CancellationToken ct)
    {
        var course = await db.Courses.AsNoTracking()
            .Where(c => c.Id == courseId)
            .Select(c => new { c.Status, c.AuthorId })
            .FirstOrDefaultAsync(ct);

        if (course is null)
            return CourseErrors.NotFound(courseId);

        // Черновик виден только автору (то же правило, что и в CourseService)
        if (course.Status != CourseStatus.Published && course.AuthorId != userId)
            return CourseErrors.NotFound(courseId);

        var lessons = await db.Lessons.AsNoTracking()
            .Where(l => l.CourseId == courseId)
            .OrderBy(l => l.OrderIndex)
            .ToListAsync(ct);

        var hasFullAccess = await HasFullAccessAsync(courseId, course.AuthorId, userId, ct);

        IReadOnlyList<LessonDto> result = lessons
            .Select(l => hasFullAccess || l.IsFree ? LessonDto.Full(l) : LessonDto.Preview(l))
            .ToList();

        return Result.Success(result);
    }

    public async Task<Result<LessonDto>> GetLessonAsync(
        Guid courseId, Guid lessonId, Guid? userId, CancellationToken ct)
    {
        var lesson = await db.Lessons.AsNoTracking()
            .FirstOrDefaultAsync(l => l.Id == lessonId && l.CourseId == courseId, ct);

        if (lesson is null)
            return LessonErrors.NotFound(lessonId);

        // Бесплатный урок доступен всем, включая анонимов
        if (lesson.IsFree)
            return Result.Success(LessonDto.Full(lesson));

        // Платный урок анонимному пользователю отдаём только как превью.
        // Порядок проверок здесь принципиален: если сначала проверять
        // userId.HasValue, аноним провалится мимо всей проверки доступа
        // и получит полный контент.
        if (userId is null)
            return Result.Success(LessonDto.Preview(lesson));

        var authorId = await db.Courses.AsNoTracking()
            .Where(c => c.Id == courseId)
            .Select(c => c.AuthorId)
            .FirstOrDefaultAsync(ct);

        var hasFullAccess = await HasFullAccessAsync(courseId, authorId, userId, ct);

        return Result.Success(hasFullAccess ? LessonDto.Full(lesson) : LessonDto.Preview(lesson));
    }

    /// <summary>Полный контент видят автор курса и студенты с активной записью.</summary>
    private async Task<bool> HasFullAccessAsync(Guid courseId, Guid authorId, Guid? userId, CancellationToken ct)
    {
        if (userId is null) return false;
        if (userId == authorId) return true;

        return await db.Enrollments.AnyAsync(
            e => e.CourseId == courseId
                 && e.UserId == userId.Value
                 && e.Status == EnrollmentStatus.Active,
            ct);
    }
}
