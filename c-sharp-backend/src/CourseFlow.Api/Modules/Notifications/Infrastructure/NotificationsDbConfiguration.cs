using CourseFlow.Api.Modules.Notifications.Domain;
using CourseFlow.Api.Modules.Users.Domain;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace CourseFlow.Api.Modules.Notifications.Infrastructure;

public sealed class NotificationConfiguration : IEntityTypeConfiguration<Notification>
{
    public void Configure(EntityTypeBuilder<Notification> builder)
    {
        builder.ToTable("notifications");
        builder.HasKey(n => n.Id);
        builder.Property(n => n.Id).ValueGeneratedNever(); // Guid v7 задаётся в коде

        builder.Property(n => n.Title).IsRequired().HasMaxLength(200);
        builder.Property(n => n.Body).IsRequired().HasMaxLength(2000);
        builder.Property(n => n.Type).HasConversion<string>().HasMaxLength(30);
        builder.Property(n => n.ActionUrl).HasMaxLength(2000);

        builder.HasOne<User>().WithMany().HasForeignKey(n => n.UserId).OnDelete(DeleteBehavior.Cascade);

        // Частичный индекс под самый частый запрос — непрочитанные уведомления пользователя (Глава 9.6)
        builder.HasIndex(n => new { n.UserId, n.CreatedAt });
        builder.HasIndex(n => n.UserId).HasFilter("is_read = false").HasDatabaseName("ix_notifications_unread");
    }
}
