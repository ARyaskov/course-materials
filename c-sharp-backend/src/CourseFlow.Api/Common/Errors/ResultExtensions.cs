namespace CourseFlow.Api.Common.Errors;

/// <summary>
/// Маппинг Result → HTTP (Глава 7.6 "Error mapping"). Единственное место в приложении,
/// где ErrorType превращается в статус-код; endpoints вызывают ToHttpResult и не думают о кодах.
/// </summary>
public static class ResultExtensions
{
    public static IResult ToHttpResult<T>(this Result<T> result, Func<T, IResult> onSuccess) =>
        result.IsSuccess ? onSuccess(result.Value) : result.Error.ToHttpResult();

    public static IResult ToHttpResult(this Result result, IResult onSuccess) =>
        result.IsSuccess ? onSuccess : result.Error.ToHttpResult();

    public static IResult ToHttpResult(this Error error)
    {
        var extensions = new Dictionary<string, object?> { ["code"] = error.Code };

        return error.Type switch
        {
            ErrorType.NotFound => Results.Problem(
                statusCode: StatusCodes.Status404NotFound, title: "Not found",
                detail: error.Description, extensions: extensions),
            ErrorType.Conflict => Results.Problem(
                statusCode: StatusCodes.Status409Conflict, title: "Conflict",
                detail: error.Description, extensions: extensions),
            ErrorType.Forbidden => Results.Problem(
                statusCode: StatusCodes.Status403Forbidden, title: "Forbidden",
                detail: error.Description, extensions: extensions),
            ErrorType.Unauthorized => Results.Problem(
                statusCode: StatusCodes.Status401Unauthorized, title: "Unauthorized",
                detail: error.Description, extensions: extensions),
            ErrorType.Validation => Results.Problem(
                statusCode: StatusCodes.Status422UnprocessableEntity, title: "Validation failed",
                detail: error.Description, extensions: extensions),
            ErrorType.TooManyRequests => Results.Problem(
                statusCode: StatusCodes.Status429TooManyRequests, title: "Too many requests",
                detail: error.Description, extensions: extensions),
            ErrorType.ExternalService => Results.Problem(
                statusCode: StatusCodes.Status502BadGateway, title: "Upstream service unavailable",
                detail: error.Description, extensions: extensions),
            // Детали внутренней ошибки клиенту не отдаём
            _ => Results.Problem(
                statusCode: StatusCodes.Status500InternalServerError, title: "Internal server error")
        };
    }
}
