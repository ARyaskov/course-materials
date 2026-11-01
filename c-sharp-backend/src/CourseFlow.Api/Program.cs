using System.Text.Json.Serialization;
using System.Threading.RateLimiting;
using CourseFlow.Api;
using CourseFlow.Api.Common.Auth;
using CourseFlow.Api.Common.Middleware;
using CourseFlow.Api.GraphQL;
using CourseFlow.Api.Infrastructure.Caching;
using CourseFlow.Api.Infrastructure.Data;
using CourseFlow.Api.Infrastructure.Messaging;
using FluentValidation;
using Microsoft.EntityFrameworkCore;
using OpenTelemetry.Metrics;
using Scalar.AspNetCore;
using Serilog;

// Bootstrap-логгер ловит ошибки до того, как построен host (Глава 18.2)
Log.Logger = new LoggerConfiguration()
    .WriteTo.Console()
    .CreateBootstrapLogger();

try
{
    var builder = WebApplication.CreateBuilder(args);

    builder.Host.UseSerilog((ctx, services, cfg) => cfg
        .ReadFrom.Configuration(ctx.Configuration)
        .ReadFrom.Services(services)
        .Enrich.FromLogContext()
        .Enrich.WithProperty("Application", "CourseFlow.Api"));

    // OpenTelemetry, health checks, service discovery, resilience (Глава 21.6)
    builder.AddServiceDefaults();
    // Метрики дополнительно отдаём Prometheus-у в pull-модели через /metrics (Глава 18.5)
    builder.Services.AddOpenTelemetry().WithMetrics(metrics => metrics.AddPrometheusExporter());

    // Database: Aspire-интеграция читает ConnectionStrings:courseflow,
    // добавляет health check с тегом "ready" и трассировку Npgsql (Глава 9, 21)
    builder.AddNpgsqlDbContext<AppDbContext>("courseflow",
        configureDbContextOptions: o => o.UseSnakeCaseNamingConvention());
    // Фабрика контекстов для GraphQL: параллельные резолверы не могут делить один DbContext (Глава 11.4)
    builder.Services.AddDbContextFactory<AppDbContext>(lifetime: ServiceLifetime.Scoped);

    // Cache: IDistributedCache + IConnectionMultiplexer поверх Redis (Глава 14)
    builder.AddRedisDistributedCache("redis");
    builder.Services.AddSingleton<IIdempotencyStore, RedisIdempotencyStore>();

    // Messaging: RabbitMQ + MassTransit + Outbox (Глава 17)
    builder.Services.AddMessaging(builder.Configuration);

    // Auth: JWT для REST, GraphQL и SignalR + политики (Глава 13)
    builder.Services.AddJwtAuthentication(builder.Configuration);

    // API. Enum-ы в JSON — строками ("Video", а не 0): контракт читаем и не ломается при перестановке членов (Глава 6.4)
    builder.Services.ConfigureHttpJsonOptions(o =>
        o.SerializerOptions.Converters.Add(new JsonStringEnumConverter()));
    builder.Services.AddValidatorsFromAssemblyContaining<Program>();
    builder.Services.AddOpenApi();
    builder.Services.AddSignalR();

    // Единый формат ошибок: Problem Details + глобальный обработчик исключений (Глава 6.7)
    builder.Services.AddProblemDetails(options =>
        options.CustomizeProblemDetails = ctx =>
        {
            ctx.ProblemDetails.Instance = $"{ctx.HttpContext.Request.Method} {ctx.HttpContext.Request.Path}";
            if (ctx.HttpContext.Items.TryGetValue(CorrelationIdMiddleware.HeaderName, out var correlationId))
                ctx.ProblemDetails.Extensions["correlationId"] = correlationId;
        });
    builder.Services.AddExceptionHandler<GlobalExceptionHandler>();

    // CORS и rate limiting (Глава 13.9)
    builder.Services.AddCors(options => options.AddPolicy("Frontend", policy => policy
        .WithOrigins(builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [])
        .AllowAnyHeader()
        .AllowAnyMethod()
        .AllowCredentials()));

    builder.Services.AddRateLimiter(options =>
    {
        options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
        // Отдельная политика для логина: защита от перебора паролей по IP
        options.AddPolicy("login", context =>
            RateLimitPartition.GetFixedWindowLimiter(
                context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
                _ => new FixedWindowRateLimiterOptions
                {
                    PermitLimit = builder.Configuration.GetValue("RateLimiting:LoginPerMinute", 5),
                    Window = TimeSpan.FromMinutes(1),
                    QueueLimit = 0
                }));
    });

    // GraphQL (Глава 11). Real-time — через SignalR, поэтому GraphQL-подписки не подключаем:
    // они потребовали бы отдельного backing store (in-memory или Redis)
    builder.Services
        .AddGraphQLServer()
        .AddQueryType<Query>()
        .AddMutationType<Mutation>()
        .AddAuthorization()
        .AddFiltering()
        .AddSorting()
        .RegisterDbContextFactory<AppDbContext>()
        .ModifyRequestOptions(o => o.IncludeExceptionDetails = builder.Environment.IsDevelopment());

    // Health checks зависимостей для readiness (Глава 18.8). Postgres и Redis добавляют Aspire-интеграции;
    // шину сообщений MassTransit регистрирует сам (masstransit-bus, тег "ready")
    builder.Services.AddHealthChecks()
        .AddDbContextCheck<AppDbContext>("database", tags: ["ready"]);

    // Modules
    builder.Services.AddModules();

    var app = builder.Build();

    // --- Middleware pipeline. Порядок здесь не произвольный (Глава 5.5) ---

    // 1. Первым: за reverse proxy восстанавливаем реальный IP и схему.
    //    Всё, что ниже (логи, rate limiting, редиректы), должно видеть их корректно.
    app.UseForwardedHeaders();

    // 2. Correlation ID — до логирования и до обработчика ошибок,
    //    чтобы идентификатор попал и в логи, и в тело ошибки.
    app.UseCorrelationId();

    // 3. Обработчик исключений: ловит всё, что упало ниже по конвейеру,
    //    и отдаёт Problem Details вместо голого 500.
    app.UseExceptionHandler();
    app.UseStatusCodePages(); // 401/403/404 без тела тоже станут problem+json

    // 4. Логирование запросов одной строкой на запрос
    app.UseSerilogRequestLogging(o =>
        o.EnrichDiagnosticContext = (diag, http) =>
            diag.Set("UserId", http.User.Identity?.IsAuthenticated == true ? http.User.Identity.Name : null));

    if (!app.Environment.IsDevelopment())
    {
        app.UseHsts();
        app.UseHttpsRedirection();
    }

    // 5. Security headers (Глава 13.9)
    app.Use(async (ctx, next) =>
    {
        ctx.Response.Headers.Append("X-Content-Type-Options", "nosniff");
        ctx.Response.Headers.Append("X-Frame-Options", "DENY");
        ctx.Response.Headers.Append("Referrer-Policy", "strict-origin-when-cross-origin");
        await next(ctx);
    });

    app.UseCors("Frontend");
    app.UseRateLimiter();

    app.UseAuthentication();
    app.UseAuthorization();

    // --- Миграции и демо-данные ---
    // Автоприменение только вне production. В production схема накатывается
    // отдельным шагом деплоя (Глава 20.7), иначе несколько инстансов
    // начнут мигрировать одновременно.
    if (!app.Environment.IsProduction())
    {
        await app.MigrateAsync();

        if (app.Configuration.GetValue("Seed:Enabled", false))
            await app.SeedAsync();
    }

    // --- Endpoints ---
    if (app.Environment.IsDevelopment())
    {
        app.MapOpenApi();
        // Scalar, а не Swagger UI: встроенный Microsoft.AspNetCore.OpenApi генерирует только схему
        app.MapScalarApiReference();
        app.MapGet("/", () => Results.Redirect("/scalar/v1")).ExcludeFromDescription();
    }

    app.MapGraphQL();
    app.MapPrometheusScrapingEndpoint(); // /metrics для Prometheus (Глава 18.5)
    app.MapDefaultEndpoints();           // /health/live и /health/ready

    // Module endpoints: REST + SignalR hub
    app.MapModules();

    app.Lifetime.ApplicationStopped.Register(Log.CloseAndFlush);

    await app.RunAsync();
}
catch (Exception ex) when (ex is not HostAbortedException)
{
    Log.Fatal(ex, "Application terminated unexpectedly");
}
finally
{
    Log.CloseAndFlush();
}

// Точка входа делается partial для интеграционных тестов (WebApplicationFactory<Program>, Глава 19.4)
public partial class Program;
