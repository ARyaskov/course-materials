namespace CourseFlow.Contracts;

/// <summary>
/// Межмодульные события CourseFlow (Глава 17 "Messaging", Глава 23).
/// Контракты — неизменяемые records: MassTransit сериализует их в JSON,
/// а имя типа (namespace + class) становится именем exchange в RabbitMQ.
/// </summary>

/// <summary>Платёж завершён успешно. Публикует Billing, потребляет Enrollment.</summary>
public record PaymentCompleted(
    Guid PaymentId,
    Guid CourseId,
    Guid UserId,
    decimal Amount,
    DateTimeOffset PaidAt);

/// <summary>Студент зачислен на курс. Публикует Enrollment, потребляют Progress и Notifications.</summary>
public record EnrollmentCreated(
    Guid EnrollmentId,
    Guid CourseId,
    Guid UserId,
    DateTimeOffset EnrolledAt);

/// <summary>Курс опубликован. Публикует Courses, потребляет Notifications.</summary>
public record CoursePublished(
    Guid CourseId,
    string Title,
    Guid AuthorId,
    DateTimeOffset PublishedAt);

/// <summary>Студент завершил все уроки курса. Публикует Progress, потребляют Enrollment и Notifications.</summary>
public record CourseCompleted(
    Guid EnrollmentId,
    Guid CourseId,
    Guid UserId,
    DateTimeOffset CompletedAt);
