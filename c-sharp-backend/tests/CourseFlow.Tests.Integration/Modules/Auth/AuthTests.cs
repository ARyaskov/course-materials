using System.Net;
using System.Net.Http.Json;
using CourseFlow.Api.Modules.Users;
using CourseFlow.Tests.Integration.Fixtures;

namespace CourseFlow.Tests.Integration.Modules.Auth;

[Collection("Integration")]
public class AuthTests(IntegrationTestFactory factory)
{
    private readonly HttpClient _anon = factory.CreateClient();

    [Fact]
    public async Task Register_ValidRequest_Returns201WithTokens()
    {
        var response = await _anon.PostAsJsonAsync("/api/v1/auth/register", new
        {
            email = $"{Guid.NewGuid():N}@test.io",
            password = "Passw0rd!",
            firstName = "Int",
            lastName = "Test"
        });

        response.StatusCode.Should().Be(HttpStatusCode.Created);
        var tokens = await response.Content.ReadFromJsonAsync<AuthTokens>();
        tokens!.AccessToken.Should().NotBeNullOrEmpty();
        tokens.RefreshToken.Should().NotBeNullOrEmpty();
    }

    [Fact]
    public async Task Register_InvalidBody_Returns422WithErrors()
    {
        var response = await _anon.PostAsJsonAsync("/api/v1/auth/register",
            new { email = "not-an-email", password = "1", firstName = "", lastName = "" });

        response.StatusCode.Should().Be(HttpStatusCode.UnprocessableEntity);
        var problem = await response.Content.ReadFromJsonAsync<ValidationProblem>();
        problem!.Errors.Should().ContainKeys("Email", "Password", "FirstName", "LastName");
    }

    [Fact]
    public async Task Register_DuplicateEmail_Returns409()
    {
        var email = $"{Guid.NewGuid():N}@test.io";
        var body = new { email, password = "Passw0rd!", firstName = "A", lastName = "B" };

        await _anon.PostAsJsonAsync("/api/v1/auth/register", body);
        var second = await _anon.PostAsJsonAsync("/api/v1/auth/register", body);

        second.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task Login_WrongPassword_Returns401()
    {
        var email = $"{Guid.NewGuid():N}@test.io";
        await _anon.PostAsJsonAsync("/api/v1/auth/register",
            new { email, password = "Passw0rd!", firstName = "A", lastName = "B" });

        var response = await _anon.PostAsJsonAsync("/api/v1/auth/login", new { email, password = "wrong-Passw0rd" });

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task Refresh_RotatesToken_AndDetectsReuse()
    {
        var email = $"{Guid.NewGuid():N}@test.io";
        var register = await _anon.PostAsJsonAsync("/api/v1/auth/register",
            new { email, password = "Passw0rd!", firstName = "A", lastName = "B" });
        var initial = (await register.Content.ReadFromJsonAsync<AuthTokens>())!;

        // Первая ротация — успех, старый токен отозван
        var first = await _anon.PostAsJsonAsync("/api/v1/auth/refresh", new { refreshToken = initial.RefreshToken });
        first.StatusCode.Should().Be(HttpStatusCode.OK);
        var rotated = (await first.Content.ReadFromJsonAsync<AuthTokens>())!;
        rotated.RefreshToken.Should().NotBe(initial.RefreshToken);

        // Повторное использование старого токена — reuse detection: 401 и все сессии отозваны
        var reuse = await _anon.PostAsJsonAsync("/api/v1/auth/refresh", new { refreshToken = initial.RefreshToken });
        reuse.StatusCode.Should().Be(HttpStatusCode.Unauthorized);

        var afterReuse = await _anon.PostAsJsonAsync("/api/v1/auth/refresh", new { refreshToken = rotated.RefreshToken });
        afterReuse.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task ProtectedEndpoint_WithoutToken_Returns401ProblemDetails()
    {
        var response = await _anon.GetAsync("/api/v1/enrollments");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        response.Content.Headers.ContentType!.MediaType.Should().Be("application/problem+json");
    }

    [Fact]
    public async Task ProtectedEndpoint_WithExpiredToken_Returns401()
    {
        var userId = await factory.CreateUserAsync();
        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new("Bearer",
            factory.GenerateToken(userId, lifetime: TimeSpan.FromMinutes(-5)));

        var response = await client.GetAsync("/api/v1/users/me");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task Me_ReturnsCurrentUser()
    {
        var (client, userId) = await factory.CreateUserClientAsync();

        var me = await client.GetFromJsonAsync<UserDto>("/api/v1/users/me");

        me!.Id.Should().Be(userId);
        me.Role.Should().Be("Student");
    }

    private sealed record ValidationProblem(int Status, Dictionary<string, string[]> Errors);
}
