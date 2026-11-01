using CourseFlow.Api.Common.Errors;
using CourseFlow.Api.Modules.Users.Domain;
using FluentValidation;

namespace CourseFlow.Api.Modules.Users;

public record RegisterRequest(string Email, string Password, string FirstName, string LastName);
public record LoginRequest(string Email, string Password);
public record RefreshRequest(string RefreshToken);
public record AuthTokens(string AccessToken, string RefreshToken);

public record UserDto(Guid Id, string Email, string FirstName, string LastName, string Role, DateTimeOffset CreatedAt)
{
    public static UserDto FromDomain(User user) =>
        new(user.Id, user.Email, user.FirstName, user.LastName, user.Role.ToString(), user.CreatedAt);
}

/// <summary>Именованные ошибки модуля (Глава 7.5): стабильные коды для клиента.</summary>
public static class UserErrors
{
    public static readonly Error EmailAlreadyRegistered =
        new("User.EmailAlreadyRegistered", "A user with this email is already registered", ErrorType.Conflict);

    public static readonly Error InvalidCredentials =
        new("User.InvalidCredentials", "Invalid email or password", ErrorType.Unauthorized);

    public static readonly Error InvalidRefreshToken =
        new("User.InvalidRefreshToken", "Refresh token is invalid or expired", ErrorType.Unauthorized);

    public static readonly Error Inactive =
        new("User.Inactive", "User account is deactivated", ErrorType.Forbidden);

    public static Error NotFound(Guid id) =>
        new("User.NotFound", $"User '{id}' was not found", ErrorType.NotFound);

    public static readonly Error CannotFollowSelf =
        new("User.CannotFollowSelf", "You cannot follow yourself", ErrorType.Validation);
}

public sealed class RegisterRequestValidator : AbstractValidator<RegisterRequest>
{
    public RegisterRequestValidator()
    {
        RuleFor(x => x.Email).NotEmpty().EmailAddress().MaximumLength(256);
        RuleFor(x => x.Password).NotEmpty().MinimumLength(8).MaximumLength(128)
            .Matches("[A-Z]").WithMessage("Password must contain an uppercase letter")
            .Matches("[0-9]").WithMessage("Password must contain a digit");
        RuleFor(x => x.FirstName).NotEmpty().MaximumLength(100);
        RuleFor(x => x.LastName).NotEmpty().MaximumLength(100);
    }
}

public sealed class LoginRequestValidator : AbstractValidator<LoginRequest>
{
    public LoginRequestValidator()
    {
        RuleFor(x => x.Email).NotEmpty().EmailAddress();
        RuleFor(x => x.Password).NotEmpty();
    }
}

public sealed class RefreshRequestValidator : AbstractValidator<RefreshRequest>
{
    public RefreshRequestValidator() => RuleFor(x => x.RefreshToken).NotEmpty();
}
