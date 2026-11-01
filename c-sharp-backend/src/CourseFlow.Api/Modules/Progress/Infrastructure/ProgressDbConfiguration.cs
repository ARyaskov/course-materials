using CourseFlow.Api.Modules.Lessons.Domain;
using CourseFlow.Api.Modules.Progress.Domain;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace CourseFlow.Api.Modules.Progress.Infrastructure;

public sealed class LessonProgressConfiguration : IEntityTypeConfiguration<LessonProgress>
{
    public void Configure(EntityTypeBuilder<LessonProgress> builder)
    {
        builder.ToTable("lesson_progress");
        builder.HasKey(p => p.Id);
        builder.Property(p => p.Id).ValueGeneratedNever(); // Guid v7 задаётся в коде

        builder.Property(p => p.Status).HasConversion<string>().HasMaxLength(20);

        builder.HasOne<Enrollment.Domain.Enrollment>().WithMany()
            .HasForeignKey(p => p.EnrollmentId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne<Lesson>().WithMany()
            .HasForeignKey(p => p.LessonId).OnDelete(DeleteBehavior.Cascade);

        builder.HasIndex(p => new { p.EnrollmentId, p.LessonId }).IsUnique();
        builder.HasIndex(p => new { p.UserId, p.CourseId });
    }
}
