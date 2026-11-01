using CourseFlow.Api.Modules.Lessons.Domain;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace CourseFlow.Api.Modules.Lessons.Infrastructure;

public sealed class LessonConfiguration : IEntityTypeConfiguration<Lesson>
{
    public void Configure(EntityTypeBuilder<Lesson> builder)
    {
        builder.ToTable("lessons");
        builder.HasKey(l => l.Id);
        builder.Property(l => l.Id).ValueGeneratedNever(); // Guid v7 задаётся в коде

        builder.Property(l => l.Title).IsRequired().HasMaxLength(200);
        builder.Property(l => l.Description).HasMaxLength(2000);
        builder.Property(l => l.Type).HasConversion<string>().HasMaxLength(20);
        builder.Property(l => l.ContentUrl).HasMaxLength(2000);
        builder.Property(l => l.TextContent).HasColumnType("text");

        // Уроки всегда читаются по курсу и в порядке OrderIndex.
        // Уникальность порядка намеренно не навязываем constraint-ом: при перестановке
        // уроков EF обновляет строки по одной, и промежуточные дубликаты сорвали бы транзакцию
        builder.HasIndex(l => new { l.CourseId, l.OrderIndex });
    }
}
