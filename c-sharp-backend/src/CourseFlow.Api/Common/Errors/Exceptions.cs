namespace CourseFlow.Api.Common.Errors;

/// <summary>
/// Исключения для ситуаций, которые НЕ являются ожидаемым исходом операции
/// и где Result неуместен: нарушение инварианта домена, отказ внешней системы,
/// сообщение из очереди, которое нельзя обработать (уйдёт в retry/DLQ).
/// Маппятся в Problem Details глобальным обработчиком (Глава 6.7).
/// </summary>
public class NotFoundException(string message) : Exception(message);

public class ConflictException(string message) : Exception(message);

public class ForbiddenException(string message) : Exception(message);

/// <summary>Платёжный шлюз отклонил операцию (Глава 23.7, mock gateway).</summary>
public class PaymentDeclinedException(string message) : Exception(message);
