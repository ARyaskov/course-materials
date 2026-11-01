using CourseFlow.Api.Common.Auth;
using CourseFlow.Api.Common.Errors;
using CourseFlow.Api.Common.Validation;
using CourseFlow.Api.Modules.Users.Infrastructure;
using CourseFlow.Api.Modules.Users.Services;

namespace CourseFlow.Api.Modules.Users.Endpoints;

/// <summary>Регистрация сервисов и endpoints модуля Users (Глава 8: Vertical Slice в Modular Monolith).</summary>
public static class UsersModule
{
    public static IServiceCollection AddUsersModule(this IServiceCollection services)
    {
        services.AddScoped<AuthService>();
        services.AddScoped<UserService>();
        services.AddHostedService<RefreshTokenCleanupWorker>(); // Глава 16: фоновая очистка токенов
        return services;
    }

    public static IEndpointRouteBuilder MapUsers(this IEndpointRouteBuilder app)
    {
        var auth = app.MapGroup("/api/v1/auth").WithTags("Auth");

        auth.MapPost("/register", RegisterAsync)
            .WithValidation<RegisterRequest>()
            .Produces<AuthTokens>(StatusCodes.Status201Created)
            .ProducesProblem(StatusCodes.Status409Conflict);

        // Rate limiting по IP (Глава 14.5): защита от перебора паролей
        auth.MapPost("/login", LoginAsync)
            .WithValidation<LoginRequest>()
            .RequireRateLimiting("login")
            .Produces<AuthTokens>()
            .ProducesProblem(StatusCodes.Status401Unauthorized);

        auth.MapPost("/refresh", RefreshAsync)
            .WithValidation<RefreshRequest>()
            .Produces<AuthTokens>()
            .ProducesProblem(StatusCodes.Status401Unauthorized);

        var users = app.MapGroup("/api/v1/users").WithTags("Users").RequireAuthorization();

        users.MapGet("/me", GetCurrentUserAsync).Produces<UserDto>();
        users.MapGet("/{id:guid}", GetByIdAsync).Produces<UserDto>().ProducesProblem(StatusCodes.Status404NotFound);
        users.MapPost("/{id:guid}/follow", FollowAsync).Produces(StatusCodes.Status204NoContent);
        users.MapDelete("/{id:guid}/follow", UnfollowAsync).Produces(StatusCodes.Status204NoContent);

        return app;
    }

    private static async Task<IResult> RegisterAsync(
        RegisterRequest request, AuthService authService, CancellationToken ct)
    {
        var result = await authService.RegisterAsync(request, ct);
        return result.ToHttpResult(tokens => Results.Created("/api/v1/users/me", tokens));
    }

    private static async Task<IResult> LoginAsync(
        LoginRequest request, AuthService authService, CancellationToken ct)
    {
        var result = await authService.LoginAsync(request, ct);
        return result.ToHttpResult(Results.Ok);
    }

    private static async Task<IResult> RefreshAsync(
        RefreshRequest request, AuthService authService, CancellationToken ct)
    {
        var result = await authService.RefreshAsync(request, ct);
        return result.ToHttpResult(Results.Ok);
    }

    private static async Task<IResult> GetCurrentUserAsync(
        UserService userService, ICurrentUser currentUser, CancellationToken ct)
    {
        var result = await userService.GetByIdAsync(currentUser.RequiredUserId(), ct);
        return result.ToHttpResult(Results.Ok);
    }

    private static async Task<IResult> GetByIdAsync(
        Guid id, UserService userService, CancellationToken ct)
    {
        var result = await userService.GetByIdAsync(id, ct);
        return result.ToHttpResult(Results.Ok);
    }

    private static async Task<IResult> FollowAsync(
        Guid id, UserService userService, ICurrentUser currentUser, CancellationToken ct)
    {
        var result = await userService.FollowAsync(currentUser.RequiredUserId(), id, ct);
        return result.ToHttpResult(Results.NoContent());
    }

    private static async Task<IResult> UnfollowAsync(
        Guid id, UserService userService, ICurrentUser currentUser, CancellationToken ct)
    {
        var result = await userService.UnfollowAsync(currentUser.RequiredUserId(), id, ct);
        return result.ToHttpResult(Results.NoContent());
    }
}
