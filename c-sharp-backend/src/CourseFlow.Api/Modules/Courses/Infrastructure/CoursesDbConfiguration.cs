using CourseFlow.Api.Modules.Courses.Domain;
using CourseFlow.Api.Modules.Users.Domain;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace CourseFlow.Api.Modules.Courses.Infrastructure;

public sealed class CourseConfiguration : IEntityTypeConfiguration<Course>
{
    public void Configure(EntityTypeBuilder<Course> builder)
    {
        builder.ToTable("courses");
        builder.HasKey(c => c.Id);
        builder.Property(c => c.Id).ValueGeneratedNever(); // Guid v7 задаётся в коде (см. UserConfiguration)

        builder.Property(c => c.Title).IsRequired().HasMaxLength(200);
        builder.Property(c => c.Description).IsRequired().HasMaxLength(5000);
        builder.Property(c => c.Price).HasPrecision(18, 2);
        builder.Property(c => c.Status).HasConversion<string>().HasMaxLength(20);
        builder.Property(c => c.ThumbnailUrl).HasMaxLength(2000);

        // Ссылка на автора без навигации: модуль Courses не ходит в таблицы модуля Users напрямую,
        // но целостность на уровне БД сохраняем
        builder.HasOne<User>().WithMany().HasForeignKey(c => c.AuthorId).OnDelete(DeleteBehavior.Restrict);

        builder.HasMany(c => c.Lessons)
            .WithOne()
            .HasForeignKey(l => l.CourseId)
            .OnDelete(DeleteBehavior.Cascade);
        builder.Navigation(c => c.Lessons).HasField("_lessons");

        builder.Ignore(c => c.CanBePublished);

        // Индексы под реальные запросы каталога (Глава 9.6)
        builder.HasIndex(c => c.AuthorId);
        builder.HasIndex(c => new { c.Status, c.PublishedAt });
        // GIN-индекс по триграммам для поиска по подстроке (Глава 9.6); расширение pg_trgm
        // объявлено в AppDbContext.OnModelCreating
        builder.HasIndex(c => c.Title).HasMethod("gin").HasOperators("gin_trgm_ops");

        // Оптимистичная блокировка через системную колонку xmin (Глава 9.8, специфично для PostgreSQL).
        // Метод UseXminAsConcurrencyToken удалён из провайдера в Npgsql EF 11 — теперь так:
        builder.Property<uint>("xmin").IsRowVersion();
    }
}
