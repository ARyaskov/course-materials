using Serilog.Context;

namespace CourseFlow.Api.Common.Middleware;

/// <summary>
/// Correlation ID (Глава 18.4): один идентификатор на всю цепочку обработки запроса.
/// Берём из входящего заголовка (его выставляет gateway или соседний сервис),
/// иначе генерируем; возвращаем в ответе и добавляем в контекст логов.
/// </summary>
public sealed class CorrelationIdMiddleware(RequestDelegate next)
{
    public const string HeaderName = "X-Correlation-ID";

    public async Task InvokeAsync(HttpContext context)
    {
        var correlationId = context.Request.Headers.TryGetValue(HeaderName, out var value)
                            && !string.IsNullOrWhiteSpace(value)
            ? value.ToString()
            : Guid.NewGuid().ToString("N");

        context.Items[HeaderName] = correlationId;
        context.Response.Headers[HeaderName] = correlationId;

        // LogContext — механизм Serilog: свойство попадёт в каждую запись лога внутри запроса
        using (LogContext.PushProperty("CorrelationId", correlationId))
        {
            await next(context);
        }
    }
}

public static class CorrelationIdMiddlewareExtensions
{
    public static IApplicationBuilder UseCorrelationId(this IApplicationBuilder app) =>
        app.UseMiddleware<CorrelationIdMiddleware>();
}
