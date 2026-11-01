using CourseFlow.Api.Modules.Courses.Domain;
using CourseFlow.Api.Modules.Users.Domain;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace CourseFlow.Api.Modules.Enrollment.Infrastructure;

public sealed class EnrollmentConfiguration : IEntityTypeConfiguration<Domain.Enrollment>
{
    public void Configure(EntityTypeBuilder<Domain.Enrollment> builder)
    {
        builder.ToTable("enrollments");
        builder.HasKey(e => e.Id);
        builder.Property(e => e.Id).ValueGeneratedNever(); // Guid v7 задаётся в коде

        builder.Property(e => e.Status).HasConversion<string>().HasMaxLength(20);

        builder.HasOne<Course>().WithMany().HasForeignKey(e => e.CourseId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne<User>().WithMany().HasForeignKey(e => e.UserId).OnDelete(DeleteBehavior.Cascade);

        // Один активный/завершённый enrollment на пару (пользователь, курс):
        // частичный уникальный индекс не мешает записаться заново после Revoked (Глава 9.6)
        builder.HasIndex(e => new { e.UserId, e.CourseId })
            .IsUnique()
            .HasFilter("status <> 'Revoked'");

        // Идемпотентность consumer-а PaymentCompleted: один платёж — одна запись
        builder.HasIndex(e => e.PaymentId).IsUnique();
    }
}
