using CourseFlow.Api.Modules.Billing.Domain;
using CourseFlow.Api.Modules.Courses.Domain;
using CourseFlow.Api.Modules.Users.Domain;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace CourseFlow.Api.Modules.Billing.Infrastructure;

public sealed class PaymentConfiguration : IEntityTypeConfiguration<Payment>
{
    public void Configure(EntityTypeBuilder<Payment> builder)
    {
        builder.ToTable("payments");
        builder.HasKey(p => p.Id);
        builder.Property(p => p.Id).ValueGeneratedNever(); // Guid v7 задаётся в коде

        builder.Property(p => p.Amount).HasPrecision(18, 2);
        builder.Property(p => p.Currency).IsRequired().HasMaxLength(3);
        builder.Property(p => p.Status).HasConversion<string>().HasMaxLength(20);
        builder.Property(p => p.TransactionId).HasMaxLength(100);
        builder.Property(p => p.FailureReason).HasMaxLength(500);

        builder.HasOne<Course>().WithMany().HasForeignKey(p => p.CourseId).OnDelete(DeleteBehavior.Restrict);
        builder.HasOne<User>().WithMany().HasForeignKey(p => p.UserId).OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(p => new { p.UserId, p.CreatedAt });
        builder.HasIndex(p => p.CourseId);
    }
}
