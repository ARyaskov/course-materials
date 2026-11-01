using FluentValidation;

namespace CourseFlow.Api.Common.Validation;

/// <summary>
/// Endpoint filter (Глава 5.6, 7.4): валидирует аргумент типа T через FluentValidation
/// и возвращает ValidationProblem (RFC 9457) со статусом 422.
/// Результирующий словарь errors группирует сообщения по имени поля.
/// </summary>
public sealed class ValidationFilter<T>(IValidator<T> validator) : IEndpointFilter
{
    public async ValueTask<object?> InvokeAsync(
        EndpointFilterInvocationContext context, EndpointFilterDelegate next)
    {
        var argument = context.Arguments.OfType<T>().FirstOrDefault();
        if (argument is null)
            return await next(context);

        var result = await validator.ValidateAsync(argument, context.HttpContext.RequestAborted);
        if (result.IsValid)
            return await next(context);

        var errors = result.Errors
            .GroupBy(e => e.PropertyName)
            .ToDictionary(g => g.Key, g => g.Select(e => e.ErrorMessage).ToArray());

        // По умолчанию ValidationProblem отдаёт 400. В CourseFlow ошибки валидации — это 422:
        // запрос синтаксически корректен, но данные не прошли правила (Глава 7.4)
        return Results.ValidationProblem(
            errors,
            statusCode: StatusCodes.Status422UnprocessableEntity,
            title: "Validation failed");
    }
}

public static class ValidationFilterExtensions
{
    public static RouteHandlerBuilder WithValidation<T>(this RouteHandlerBuilder builder) =>
        builder.AddEndpointFilter<ValidationFilter<T>>()
               .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);
}
