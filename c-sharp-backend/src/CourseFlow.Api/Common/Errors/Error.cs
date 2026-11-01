namespace CourseFlow.Api.Common.Errors;

/// <summary>
/// Типизированная бизнес-ошибка (Глава 7.5). Code — стабильный машинный идентификатор
/// для клиента, Description — человекочитаемое описание, Type — маппится в HTTP-статус.
/// </summary>
public record Error(string Code, string Description, ErrorType Type)
{
    public static readonly Error None = new(string.Empty, string.Empty, ErrorType.None);

    // Фабрики для быстрых, одноразовых ошибок.
    // Для повторяющихся ошибок модули заводят именованные константы (UserErrors, CourseErrors, ...).
    public static Error NotFound(string description, string code = "General.NotFound") =>
        new(code, description, ErrorType.NotFound);

    public static Error Conflict(string description, string code = "General.Conflict") =>
        new(code, description, ErrorType.Conflict);

    public static Error Forbidden(string description, string code = "General.Forbidden") =>
        new(code, description, ErrorType.Forbidden);

    public static Error Unauthorized(string description, string code = "General.Unauthorized") =>
        new(code, description, ErrorType.Unauthorized);

    public static Error Validation(string description, string code = "General.Validation") =>
        new(code, description, ErrorType.Validation);

    public static Error TooManyRequests(string description, string code = "General.TooManyRequests") =>
        new(code, description, ErrorType.TooManyRequests);

    public static Error ExternalService(string description, string code = "General.ExternalService") =>
        new(code, description, ErrorType.ExternalService);
}

public enum ErrorType
{
    None,
    NotFound,        // 404
    Conflict,        // 409
    Forbidden,       // 403
    Unauthorized,    // 401
    Validation,      // 422
    TooManyRequests, // 429
    ExternalService, // 502
    Failure          // 500
}
