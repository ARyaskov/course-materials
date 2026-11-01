using System.ComponentModel.DataAnnotations;

namespace CourseFlow.Api.Common.Auth;

/// <summary>
/// Типизированные настройки JWT (Глава 4.5 "Configuration", Глава 13.4).
/// ValidateOnStart в регистрации не даст приложению стартовать с пустым секретом.
/// </summary>
public sealed class JwtOptions
{
    public const string SectionName = "Jwt";

    [Required, MinLength(32, ErrorMessage = "Jwt:SecretKey must be at least 32 characters (256 bits for HS256)")]
    public string SecretKey { get; set; } = string.Empty;

    [Required]
    public string Issuer { get; set; } = "courseflow-api";

    [Required]
    public string Audience { get; set; } = "courseflow-clients";

    [Range(1, 24 * 60)]
    public int AccessTokenMinutes { get; set; } = 15;

    [Range(1, 365)]
    public int RefreshTokenDays { get; set; } = 30;
}
