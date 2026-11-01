using CourseFlow.Api.Common.Errors;
using CourseFlow.Api.Modules.Billing.Domain;
using FluentValidation;

namespace CourseFlow.Api.Modules.Billing;

/// <summary>Тело запроса на оплату. UserId в нём нет — он берётся из JWT, а не из тела.</summary>
public record ProcessPaymentRequest(Guid CourseId, string? CardToken = null);

public record PaymentDto(
    Guid Id,
    Guid CourseId,
    decimal Amount,
    string Currency,
    string Status,
    string? TransactionId,
    DateTimeOffset CreatedAt,
    DateTimeOffset? CompletedAt)
{
    public static PaymentDto FromDomain(Payment p) => new(
        p.Id, p.CourseId, p.Amount, p.Currency, p.Status.ToString(),
        p.TransactionId, p.CreatedAt, p.CompletedAt);
}

public static class BillingErrors
{
    public static Error PaymentNotFound(Guid id) =>
        new("Billing.PaymentNotFound", $"Payment '{id}' was not found", ErrorType.NotFound);

    public static readonly Error AlreadyEnrolled =
        new("Billing.AlreadyEnrolled", "User is already enrolled in this course", ErrorType.Conflict);

    public static readonly Error OperationInProgress =
        new("Billing.OperationInProgress", "A payment with this idempotency key is already being processed", ErrorType.Conflict);

    public static Error Declined(string reason) =>
        new("Billing.Declined", $"Payment declined: {reason}", ErrorType.Validation);
}

public sealed class ProcessPaymentRequestValidator : AbstractValidator<ProcessPaymentRequest>
{
    public ProcessPaymentRequestValidator()
    {
        RuleFor(x => x.CourseId).NotEmpty();
        RuleFor(x => x.CardToken).MaximumLength(100);
    }
}
