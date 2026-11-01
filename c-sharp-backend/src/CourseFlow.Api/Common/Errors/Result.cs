namespace CourseFlow.Api.Common.Errors;

/// <summary>
/// Result — явный исход операции вместо исключений для ожидаемых ошибок (Глава 7.5).
/// Сигнатура Task&lt;Result&lt;CourseDto&gt;&gt; честно говорит вызывающему коду,
/// что метод может завершиться ошибкой, и заставляет её обработать.
/// </summary>
public class Result
{
    protected Result(bool isSuccess, Error error)
    {
        IsSuccess = isSuccess;
        Error = error;
    }

    public bool IsSuccess { get; }
    public bool IsFailure => !IsSuccess;
    public Error Error { get; }

    public static Result Success() => new(true, Error.None);
    public static Result Failure(Error error) => new(false, error);

    public static Result<T> Success<T>(T value) => new(value, true, Error.None);
    public static Result<T> Failure<T>(Error error) => new(default, false, error);

    // Позволяет писать `return UserErrors.InvalidCredentials;` в методах, возвращающих Result
    public static implicit operator Result(Error error) => Failure(error);
}

public class Result<T> : Result
{
    private readonly T? _value;

    protected internal Result(T? value, bool isSuccess, Error error)
        : base(isSuccess, error) => _value = value;

    public T Value => IsSuccess
        ? _value!
        : throw new InvalidOperationException("Cannot access value of failed result");

    public static implicit operator Result<T>(Error error) => Failure<T>(error);
}
