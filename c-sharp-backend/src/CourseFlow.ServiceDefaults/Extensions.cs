using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using OpenTelemetry;
using OpenTelemetry.Metrics;
using OpenTelemetry.Trace;

namespace Microsoft.Extensions.Hosting;

/// <summary>
/// Общие настройки для всех сервисов CourseFlow (Глава 21 "Aspire").
/// Namespace Microsoft.Extensions.Hosting выбран намеренно: так extension-методы
/// видны в Program.cs без дополнительного using.
/// </summary>
public static class Extensions
{
    public static TBuilder AddServiceDefaults<TBuilder>(this TBuilder builder)
        where TBuilder : IHostApplicationBuilder
    {
        builder.ConfigureOpenTelemetry();

        builder.AddDefaultHealthChecks();

        builder.Services.AddServiceDiscovery();

        builder.Services.ConfigureHttpClientDefaults(http =>
        {
            // Retry, circuit breaker и timeout по умолчанию для всех HttpClient (Глава 15)
            http.AddStandardResilienceHandler();
            http.AddServiceDiscovery();
        });

        return builder;
    }

    public static TBuilder ConfigureOpenTelemetry<TBuilder>(this TBuilder builder)
        where TBuilder : IHostApplicationBuilder
    {
        builder.Logging.AddOpenTelemetry(logging =>
        {
            logging.IncludeFormattedMessage = true;
            logging.IncludeScopes = true;
        });

        builder.Services.AddOpenTelemetry()
            .WithMetrics(metrics =>
            {
                metrics.AddAspNetCoreInstrumentation()
                    .AddHttpClientInstrumentation()
                    .AddRuntimeInstrumentation()
                    // Собственные метрики приложения (Глава 18.5: IMeterFactory)
                    .AddMeter("CourseFlow.*");
            })
            .WithTracing(tracing =>
            {
                tracing.AddAspNetCoreInstrumentation(o =>
                        // Health checks и метрики не должны засорять трейсы
                        o.Filter = ctx => !ctx.Request.Path.StartsWithSegments("/health")
                                          && !ctx.Request.Path.StartsWithSegments("/metrics"))
                    .AddHttpClientInstrumentation()
                    // ActivitySource-ы библиотек: SQL-запросы Npgsql и сообщения MassTransit
                    .AddSource("Npgsql")
                    .AddSource("MassTransit")
                    .AddSource("CourseFlow.*");
            });

        builder.AddOpenTelemetryExporters();

        return builder;
    }

    private static TBuilder AddOpenTelemetryExporters<TBuilder>(this TBuilder builder)
        where TBuilder : IHostApplicationBuilder
    {
        // OTLP — единый протокол для Aspire Dashboard, Jaeger и OpenTelemetry Collector.
        // Экспортёр включается, только если задан endpoint: локально без него ничего не ломается.
        var useOtlpExporter = !string.IsNullOrWhiteSpace(
            builder.Configuration["OTEL_EXPORTER_OTLP_ENDPOINT"]);

        if (useOtlpExporter)
        {
            builder.Services.AddOpenTelemetry().UseOtlpExporter();
        }

        return builder;
    }

    public static TBuilder AddDefaultHealthChecks<TBuilder>(this TBuilder builder)
        where TBuilder : IHostApplicationBuilder
    {
        builder.Services.AddHealthChecks()
            // Liveness: процесс жив. Зависимости здесь не проверяем (Глава 18.8)
            .AddCheck("self", () => HealthCheckResult.Healthy(), tags: ["live"]);

        return builder;
    }

    /// <summary>
    /// /health/live — только факт живости процесса; /health/ready — зависимости с тегом "ready".
    /// Разделение принципиально для Kubernetes: падение Redis не должно перезапускать под.
    /// </summary>
    public static WebApplication MapDefaultEndpoints(this WebApplication app)
    {
        app.MapHealthChecks("/health/live", new HealthCheckOptions
        {
            Predicate = check => check.Tags.Contains("live")
        });

        app.MapHealthChecks("/health/ready", new HealthCheckOptions
        {
            Predicate = check => check.Tags.Contains("ready")
        });

        return app;
    }
}
