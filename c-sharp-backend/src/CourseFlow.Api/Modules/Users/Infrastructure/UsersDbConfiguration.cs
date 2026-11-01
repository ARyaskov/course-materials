using CourseFlow.Api.Modules.Users.Domain;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace CourseFlow.Api.Modules.Users.Infrastructure;

/// <summary>EF-конфигурация модуля Users (Глава 9.4: IEntityTypeConfiguration вместо OnModelCreating-простыни).</summary>
public sealed class UserConfiguration : IEntityTypeConfiguration<User>
{
    public void Configure(EntityTypeBuilder<User> builder)
    {
        builder.ToTable("users");
        builder.HasKey(u => u.Id);
        // Guid v7 генерируется в коде (Guid.CreateVersion7): без ValueGeneratedNever EF считает
        // сущность с заполненным ключом уже существующей и вместо INSERT делает UPDATE (Глава 9.4)
        builder.Property(u => u.Id).ValueGeneratedNever();

        builder.Property(u => u.Email).IsRequired().HasMaxLength(256);
        builder.HasIndex(u => u.Email).IsUnique();

        builder.Property(u => u.PasswordHash).IsRequired().HasMaxLength(200);
        builder.Property(u => u.FirstName).IsRequired().HasMaxLength(100);
        builder.Property(u => u.LastName).IsRequired().HasMaxLength(100);
        builder.Property(u => u.Role).HasConversion<string>().HasMaxLength(20);

        builder.HasMany(u => u.RefreshTokens)
            .WithOne()
            .HasForeignKey(t => t.UserId)
            .OnDelete(DeleteBehavior.Cascade);

        // Коллекция закрыта приватным полем — EF пишет в него напрямую
        builder.Navigation(u => u.RefreshTokens).HasField("_refreshTokens");
    }
}

public sealed class RefreshTokenConfiguration : IEntityTypeConfiguration<RefreshToken>
{
    public void Configure(EntityTypeBuilder<RefreshToken> builder)
    {
        builder.ToTable("refresh_tokens");
        builder.HasKey(t => t.Id);
        builder.Property(t => t.Id).ValueGeneratedNever();

        builder.Property(t => t.TokenHash).IsRequired().HasMaxLength(64); // SHA-256 hex
        builder.HasIndex(t => t.TokenHash).IsUnique();
        builder.HasIndex(t => t.UserId);

        builder.Ignore(t => t.IsRevoked);
        builder.Ignore(t => t.IsExpired);
        builder.Ignore(t => t.IsActive);
    }
}

public sealed class UserFollowConfiguration : IEntityTypeConfiguration<UserFollow>
{
    public void Configure(EntityTypeBuilder<UserFollow> builder)
    {
        builder.ToTable("user_follows");
        builder.HasKey(f => new { f.FollowerId, f.FollowedUserId });

        builder.HasOne<User>().WithMany().HasForeignKey(f => f.FollowerId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne<User>().WithMany().HasForeignKey(f => f.FollowedUserId).OnDelete(DeleteBehavior.Cascade);

        builder.HasIndex(f => f.FollowedUserId);
    }
}
