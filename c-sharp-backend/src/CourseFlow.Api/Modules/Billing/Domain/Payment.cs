namespace CourseFlow.Api.Modules.Billing.Domain;

public enum PaymentStatus { Pending, Completed, Failed, Refunded }

/// <summary>Платёж (Глава 23.7). Mock-шлюз, но паттерн транзакции + Outbox — настоящий.</summary>
public class Payment
{
    public Guid Id { get; private set; } = Guid.CreateVersion7();
    public Guid CourseId { get; private set; }
    public Guid UserId { get; private set; }
    public decimal Amount { get; private set; }
    public string Currency { get; private set; } = "USD";
    public PaymentStatus Status { get; private set; }
    public string? TransactionId { get; private set; }
    public string? FailureReason { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? CompletedAt { get; private set; }

    private Payment() { } // EF Core

    public static Payment Create(Guid courseId, Guid userId, decimal amount)
    {
        if (amount < 0)
            throw new ArgumentException("Payment amount cannot be negative", nameof(amount));

        return new Payment
        {
            CourseId = courseId,
            UserId = userId,
            Amount = amount,
            Status = PaymentStatus.Pending
        };
    }

    public void Complete(string transactionId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(transactionId);
        if (Status != PaymentStatus.Pending)
            throw new InvalidOperationException($"Cannot complete payment in status {Status}");

        Status = PaymentStatus.Completed;
        TransactionId = transactionId;
        CompletedAt = DateTimeOffset.UtcNow;
    }

    public void Fail(string reason)
    {
        Status = PaymentStatus.Failed;
        FailureReason = reason;
    }
}
