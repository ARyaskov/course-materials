using CourseFlow.Api.Modules.Billing.Domain;
using CourseFlow.Api.Modules.Courses.Domain;
using CourseFlow.Api.Modules.Lessons.Domain;
using CourseFlow.Api.Modules.Notifications.Domain;
using CourseFlow.Api.Modules.Progress.Domain;
using CourseFlow.Api.Modules.Users.Domain;
using MassTransit;
using Microsoft.EntityFrameworkCore;

namespace CourseFlow.Api.Infrastructure.Data;

/// <summary>
/// Единый DbContext модульного монолита (Глава 9). Один контекст = одна транзакция
/// на бизнес-операцию, включая запись в outbox. Конфигурации сущностей живут
/// в модулях (IEntityTypeConfiguration) и подхватываются из сборки.
/// </summary>
public sealed class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();
    public DbSet<UserFollow> UserFollows => Set<UserFollow>();
    public DbSet<Course> Courses => Set<Course>();
    public DbSet<Lesson> Lessons => Set<Lesson>();
    public DbSet<Modules.Enrollment.Domain.Enrollment> Enrollments => Set<Modules.Enrollment.Domain.Enrollment>();
    public DbSet<LessonProgress> LessonProgresses => Set<LessonProgress>();
    public DbSet<Payment> Payments => Set<Payment>();
    public DbSet<Notification> Notifications => Set<Notification>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        // pg_trgm — для GIN-индекса по подстроке в названии курса (Глава 9.6)
        modelBuilder.HasPostgresExtension("pg_trgm");

        modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);

        // Таблицы MassTransit Outbox/Inbox (Глава 17.5): сообщения фиксируются
        // в той же транзакции, что и бизнес-данные
        modelBuilder.AddInboxStateEntity();
        modelBuilder.AddOutboxMessageEntity();
        modelBuilder.AddOutboxStateEntity();
    }
}
