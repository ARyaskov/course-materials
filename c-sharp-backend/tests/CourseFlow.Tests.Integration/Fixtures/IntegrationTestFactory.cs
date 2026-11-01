using System.Net.Http.Headers;
using System.Security.Claims;
using System.Text;
using CourseFlow.Api.Infrastructure.Data;
using CourseFlow.Api.Modules.Users.Domain;
using MassTransit;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using Testcontainers.PostgreSql;
using Testcontainers.Redis;

namespace CourseFlow.Tests.Integration.Fixtures;

/// <summary>
/// Поднимает реальные PostgreSQL и Redis в контейнерах и API поверх них (Глава 19.4, 19.9).
/// RabbitMQ заменяется MassTransit test harness (in-memory транспорт): цепочка
/// Outbox → bus → consumer выполняется по-настоящему, но без брокера.
/// </summary>
public sealed class IntegrationTestFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder()
        .WithImage("postgres:17-alpine")
        .WithDatabase("courseflow_test")
        .Build();

    private readonly RedisContainer _redis = new RedisBuilder()
        .WithImage("redis:8-alpine")
        .Build();

    // Секрет один и тот же для приложения и для генератора тестовых токенов
    private const string TestJwtSecret = "test-secret-key-minimum-32-characters-long";
    private const string TestIssuer = "courseflow-api";
    private const string TestAudience = "courseflow-clients";

    public async ValueTask InitializeAsync()
    {
        await Task.WhenAll(_postgres.StartAsync(), _redis.StartAsync());

        // Первое обращение к Services строит host: Program.cs применит миграции и сид
        using var scope = Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        await db.Database.CanConnectAsync();
    }

    public override async ValueTask DisposeAsync()
    {
        await base.DisposeAsync();
        await Task.WhenAll(_postgres.DisposeAsync().AsTask(), _redis.DisposeAsync().AsTask());
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");

        // Aspire-интеграции читают ConnectionStrings из конфигурации прямо в момент регистрации
        // (builder.AddNpgsqlDbContext в Program.cs). UseSetting попадает в конфигурацию ДО выполнения
        // Program.cs, а ConfigureAppConfiguration — уже после, поэтому здесь нужен именно UseSetting.
        // Host строится лениво, так что к этому моменту контейнеры уже запущены.
        builder.UseSetting("ConnectionStrings:courseflow", _postgres.GetConnectionString());
        builder.UseSetting("ConnectionStrings:redis", _redis.GetConnectionString());
        builder.UseSetting("Jwt:SecretKey", TestJwtSecret);
        builder.UseSetting("Jwt:Issuer", TestIssuer);
        builder.UseSetting("Jwt:Audience", TestAudience);
        builder.UseSetting("Seed:Enabled", "true");
        builder.UseSetting("RateLimiting:LoginPerMinute", "1000");
        builder.UseSetting("Serilog:MinimumLevel:Default", "Warning");

        builder.ConfigureServices(services =>
        {
            // Test harness подменяет RabbitMQ in-memory транспортом; регистрация consumer-ов,
            // outbox и retry из Program.cs остаются в силе
            services.AddMassTransitTestHarness();
        });
    }

    /// <summary>Строка подключения к контейнеру — нужна тестам consumer-ов.</summary>
    public string PostgresConnectionString => _postgres.GetConnectionString();

    /// <summary>
    /// Генерирует валидный токен без обращения к DI: параметры подписи
    /// те же, что мы подставили в конфигурацию выше.
    /// </summary>
    public string GenerateToken(Guid userId, string role = "Student", TimeSpan? lifetime = null)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(TestJwtSecret));

        var descriptor = new SecurityTokenDescriptor
        {
            Issuer = TestIssuer,
            Audience = TestAudience,
            Expires = DateTime.UtcNow.Add(lifetime ?? TimeSpan.FromHours(1)),
            SigningCredentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256),
            Claims = new Dictionary<string, object>
            {
                [JwtRegisteredClaimNames.Sub] = userId.ToString(),
                [JwtRegisteredClaimNames.Email] = $"{userId}@test.local",
                [ClaimTypes.Role] = role
            }
        };

        return new JsonWebTokenHandler().CreateToken(descriptor);
    }

    /// <summary>
    /// Создаёт пользователя прямо в БД (минуя HTTP) и возвращает его Id.
    /// Токен с несуществующим userId прошёл бы аутентификацию, но упал бы на FK при первой записи.
    /// </summary>
    public async Task<Guid> CreateUserAsync(UserRole role = UserRole.Student)
    {
        using var scope = Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        var user = User.Create($"{Guid.NewGuid():N}@test.local", "not-a-real-hash", "Test", role.ToString());
        user.SetRole(role);
        db.Users.Add(user);
        await db.SaveChangesAsync();

        return user.Id;
    }

    public HttpClient CreateClientAs(string role, Guid? userId = null)
    {
        var client = CreateClient();
        client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", GenerateToken(userId ?? Guid.NewGuid(), role));
        return client;
    }

    /// <summary>Клиент от имени только что созданного в БД пользователя с нужной ролью.</summary>
    public async Task<(HttpClient Client, Guid UserId)> CreateUserClientAsync(UserRole role = UserRole.Student)
    {
        var userId = await CreateUserAsync(role);
        return (CreateClientAs(role.ToString(), userId), userId);
    }
}

/// <summary>Один набор контейнеров на весь прогон, а не на каждый тестовый класс.</summary>
[CollectionDefinition("Integration")]
public sealed class IntegrationCollection : ICollectionFixture<IntegrationTestFactory>;
