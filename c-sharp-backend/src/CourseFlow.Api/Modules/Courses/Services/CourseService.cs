using System.Text.Json;
using CourseFlow.Api.Common.Errors;
using CourseFlow.Api.Infrastructure.Data;
using CourseFlow.Api.Modules.Courses.Domain;
using CourseFlow.Contracts;
using Dapper;
using MassTransit;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Distributed;

namespace CourseFlow.Api.Modules.Courses.Services;

/// <summary>
/// Модуль Courses (Глава 23.3): cache-aside через IDistributedCache (Redis),
/// публикация CoursePublished через Outbox, проекции в DTO внутри IQueryable.
/// </summary>
public sealed class CourseService(
    AppDbContext db,
    IDistributedCache cache,
    IPublishEndpoint publishEndpoint,
    ILogger<CourseService> logger)
{
    private const string CacheKeyPrefix = "course:";
    private static readonly TimeSpan CacheTtl = TimeSpan.FromMinutes(5);

    public async Task<CourseDto> CreateAsync(CreateCourseRequest request, Guid authorId, CancellationToken ct)
    {
        var course = Course.Create(request.Title, request.Description, authorId, request.Price);

        db.Courses.Add(course);
        await db.SaveChangesAsync(ct);

        logger.LogInformation("Course {CourseId} created by {AuthorId}", course.Id, authorId);

        return CourseDto.FromDomain(course);
    }

    public async Task<Result<CourseDto>> UpdateAsync(
        Guid courseId, UpdateCourseRequest request, Guid authorId, CancellationToken ct)
    {
        var course = await db.Courses.FirstOrDefaultAsync(c => c.Id == courseId, ct);
        if (course is null)
            return CourseErrors.NotFound(courseId);

        if (course.AuthorId != authorId)
            return CourseErrors.NotAuthor;

        if (course.Status == CourseStatus.Published)
            return CourseErrors.CannotModifyPublished;

        course.Update(request.Title, request.Description, request.Price);
        await db.SaveChangesAsync(ct);

        // Кэш инвалидируется при ЛЮБОМ изменении курса, а не только при публикации.
        // Иначе после правки названия клиенты пять минут видят старые данные.
        await InvalidateAsync(courseId, ct);

        return Result.Success(CourseDto.FromDomain(course));
    }

    public async Task<Result<CourseDto>> PublishAsync(Guid courseId, Guid authorId, CancellationToken ct)
    {
        var course = await db.Courses
            .Include(c => c.Lessons)
            .FirstOrDefaultAsync(c => c.Id == courseId, ct);

        if (course is null)
            return CourseErrors.NotFound(courseId);

        if (course.AuthorId != authorId)
            return CourseErrors.NotAuthor;

        if (course.Status == CourseStatus.Published)
            return CourseErrors.AlreadyPublished;

        if (course.Lessons.Count == 0)
            return CourseErrors.NoLessonsToPublish;

        course.Publish();

        // Публикуем событие через Outbox — сообщение попадёт в таблицу outbox
        // в той же транзакции, что и изменение статуса (Глава 17.5)
        await publishEndpoint.Publish(new CoursePublished(
            CourseId: course.Id,
            Title: course.Title,
            AuthorId: course.AuthorId,
            PublishedAt: course.PublishedAt!.Value), ct);

        await db.SaveChangesAsync(ct);
        await InvalidateAsync(courseId, ct);

        logger.LogInformation("Course {CourseId} published", course.Id);

        return Result.Success(CourseDto.FromDomain(course));
    }

    public async Task<Result<CourseDto>> GetByIdAsync(Guid courseId, Guid? requestingUserId, CancellationToken ct)
    {
        // В кэш кладём только опубликованные курсы: они одинаковы для всех.
        // Черновик зависит от того, кто спрашивает, и кэшированию не подлежит.
        var cacheKey = CacheKeyPrefix + courseId;
        var cached = await cache.GetStringAsync(cacheKey, ct);
        if (cached is not null)
            return Result.Success(JsonSerializer.Deserialize<CourseDto>(cached)!);

        var course = await db.Courses
            .AsNoTracking()
            .FirstOrDefaultAsync(c => c.Id == courseId, ct);

        if (course is null)
            return CourseErrors.NotFound(courseId);

        // Черновик виден только автору. Для остальных курса "не существует":
        // 404 вместо 403, чтобы не раскрывать факт его наличия.
        if (course.Status != CourseStatus.Published && course.AuthorId != requestingUserId)
            return CourseErrors.NotFound(courseId);

        var dto = CourseDto.FromDomain(course);

        if (course.Status == CourseStatus.Published)
        {
            await cache.SetStringAsync(cacheKey,
                JsonSerializer.Serialize(dto),
                new DistributedCacheEntryOptions { AbsoluteExpirationRelativeToNow = CacheTtl },
                ct);
        }

        return Result.Success(dto);
    }

    public async Task<PagedResult<CourseDto>> GetPublishedAsync(
        int page, int pageSize, string? search, CancellationToken ct)
    {
        var query = db.Courses
            .AsNoTracking()
            .Where(c => c.Status == CourseStatus.Published);

        if (!string.IsNullOrWhiteSpace(search))
            query = query.Where(c => EF.Functions.ILike(c.Title, $"%{search}%"));

        var total = await query.CountAsync(ct);

        // Проекция строится прямо в выражении: статический метод FromDomain
        // EF Core в SQL не транслирует и упал бы в рантайме.
        var items = await query
            .OrderByDescending(c => c.PublishedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(c => new CourseDto
            {
                Id = c.Id,
                Title = c.Title,
                Description = c.Description,
                Price = c.Price,
                Status = c.Status.ToString(),
                AuthorId = c.AuthorId,
                CreatedAt = c.CreatedAt,
                PublishedAt = c.PublishedAt
            })
            .ToListAsync(ct);

        return new PagedResult<CourseDto>(items, total, page, pageSize);
    }

    /// <summary>Курсы автора, включая черновики — только для самого автора.</summary>
    public async Task<IReadOnlyList<CourseDto>> GetMineAsync(Guid authorId, CancellationToken ct) =>
        await db.Courses.AsNoTracking()
            .Where(c => c.AuthorId == authorId)
            .OrderByDescending(c => c.CreatedAt)
            .Select(c => new CourseDto
            {
                Id = c.Id, Title = c.Title, Description = c.Description, Price = c.Price,
                Status = c.Status.ToString(), AuthorId = c.AuthorId,
                CreatedAt = c.CreatedAt, PublishedAt = c.PublishedAt
            })
            .ToListAsync(ct);

    /// <summary>
    /// Отчёт по курсу через Dapper (Глава 9.10): агрегаты по нескольким таблицам
    /// проще и быстрее написать на SQL, чем выразить через LINQ.
    /// Подзапросы вместо JOIN — чтобы не получить декартово произведение при SUM.
    /// COUNT(*) в PostgreSQL — bigint; приводим к int, иначе Dapper не найдёт подходящий конструктор record-а.
    /// </summary>
    public async Task<Result<CourseStatsDto>> GetStatsAsync(Guid courseId, Guid authorId, CancellationToken ct)
    {
        const string sql = """
            SELECT c.id            AS CourseId,
                   c.title         AS Title,
                   (SELECT COUNT(*)::int FROM lessons l WHERE l.course_id = c.id)                                    AS Lessons,
                   (SELECT COUNT(*)::int FROM enrollments e WHERE e.course_id = c.id AND e.status = 'Active')        AS ActiveEnrollments,
                   (SELECT COUNT(*)::int FROM enrollments e WHERE e.course_id = c.id AND e.status = 'Completed')     AS CompletedEnrollments,
                   (SELECT COALESCE(SUM(p.amount), 0) FROM payments p WHERE p.course_id = c.id AND p.status = 'Completed') AS Revenue
            FROM courses c
            WHERE c.id = @CourseId AND c.author_id = @AuthorId
            """;

        var connection = db.Database.GetDbConnection();
        var stats = await connection.QuerySingleOrDefaultAsync<CourseStatsDto>(
            new CommandDefinition(sql, new { CourseId = courseId, AuthorId = authorId }, cancellationToken: ct));

        // Курс чужой или не существует — одинаковый ответ, чтобы не раскрывать наличие черновиков
        return stats is null ? CourseErrors.NotFound(courseId) : Result.Success(stats);
    }

    private Task InvalidateAsync(Guid courseId, CancellationToken ct) =>
        cache.RemoveAsync(CacheKeyPrefix + courseId, ct);
}
