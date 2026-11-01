using CourseFlow.Api.Common.Errors;
using FluentValidation;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;

namespace CourseFlow.Api.Common.Middleware;

/// <summary>
/// Глобальный обработчик исключений (Глава 6.7 "REST error model").
/// Всё, что долетело сюда, превращается в RFC 9457 Problem Details:
/// клиент никогда не видит голый 500 со стек-трейсом.
/// </summary>
public sealed class GlobalExceptionHandler(
    IProblemDetailsService problemDetails,
    ILogger<GlobalExceptionHandler> logger) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(
        HttpContext ctx, Exception ex, CancellationToken ct)
    {
        var (status, title, logLevel) = ex switch
        {
            // Невалидный JSON, неверный тип поля и т.п. — ошибка клиента, а не сервера
            BadHttpRequestException bad => (bad.StatusCode, "Bad request", LogLevel.Information),
            NotFoundException        => (StatusCodes.Status404NotFound, "Not found", LogLevel.Information),
            ConflictException        => (StatusCodes.Status409Conflict, "Conflict", LogLevel.Warning),
            ForbiddenException       => (StatusCodes.Status403Forbidden, "Forbidden", LogLevel.Warning),
            ValidationException      => (StatusCodes.Status422UnprocessableEntity, "Validation failed", LogLevel.Warning),
            PaymentDeclinedException => (StatusCodes.Status402PaymentRequired, "Payment declined", LogLevel.Warning),
            // Нарушение инварианта домена (например, публикация курса без уроков) — ошибка клиента
            InvalidOperationException => (StatusCodes.Status409Conflict, "Operation not allowed", LogLevel.Warning),
            OperationCanceledException when ctx.RequestAborted.IsCancellationRequested
                                     => (499, "Client closed request", LogLevel.Debug),
            _                        => (StatusCodes.Status500InternalServerError, "Internal server error", LogLevel.Error)
        };

        logger.Log(logLevel, ex, "Exception handled: {Title} ({Status})", title, status);

        ctx.Response.StatusCode = status;

        var problem = new ProblemDetails
        {
            Title = title,
            Status = status,
            Detail = status < 500 ? ex.Message : null // детали только для 4xx
        };

        // Correlation ID попадает в тело ошибки, чтобы клиент мог сослаться на него в саппорт (Глава 18.4)
        if (ctx.Response.Headers.TryGetValue(CorrelationIdMiddleware.HeaderName, out var correlationId))
            problem.Extensions["correlationId"] = correlationId.ToString();

        return await problemDetails.TryWriteAsync(new ProblemDetailsContext
        {
            HttpContext = ctx,
            Exception = ex,
            ProblemDetails = problem
        });
    }
}
