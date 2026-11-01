using System.Diagnostics.Metrics;
using CourseFlow.Api.Common.Errors;
using CourseFlow.Api.Infrastructure.Caching;
using CourseFlow.Api.Infrastructure.Data;
using CourseFlow.Api.Modules.Billing.Domain;
using CourseFlow.Api.Modules.Courses.Domain;
using CourseFlow.Api.Modules.Enrollment.Domain;
using CourseFlow.Contracts;
using MassTransit;
using Microsoft.EntityFrameworkCore;

namespace CourseFlow.Api.Modules.Billing.Services;

/// <summary>
/// Billing mock (Глава 23.7): платёж + событие PaymentCompleted сохраняются в одной транзакции
/// (Outbox), повторные запросы с тем же Idempotency-Key не создают второго платежа (Redis, Глава 14.5).
/// </summary>
public sealed class BillingService(
    AppDbContext db,
    IPublishEndpoint publishEndpoint,
    IIdempotencyStore idempotency,
    IMeterFactory meterFactory,
    ILogger<BillingService> logger)
{
    // Собственная бизнес-метрика (Глава 18.5): счётчик платежей по статусу
    private readonly Counter<long> _payments = meterFactory
        .Create("CourseFlow.Billing")
        .CreateCounter<long>("courseflow.payments", description: "Payments processed by outcome");

    public async Task<Result<PaymentDto>> ProcessPaymentAsync(
        ProcessPaymentRequest request, Guid userId, string? idempotencyKey, CancellationToken ct)
    {
        // Ключ идемпотентности привязан к пользователю: чужой ключ не должен вернуть чужой платёж
        var key = idempotencyKey is null ? null : $"payment:{userId}:{idempotencyKey}";

        if (key is not null)
        {
            var state = await idempotency.BeginAsync<PaymentDto>(key, ct);
            switch (state.Status)
            {
                case IdempotencyStatus.Completed:
                    // Повтор уже завершённой операции — отдаём сохранённый результат
                    return Result.Success(state.Result!);
                case IdempotencyStatus.InProgress:
                    // Первый запрос ещё выполняется. 409 — сигнал клиенту повторить позже
                    return BillingErrors.OperationInProgress;
            }
        }

        try
        {
            var result = await ChargeAndSaveAsync(request, userId, ct);

            if (key is not null)
            {
                if (result.IsSuccess)
                    await idempotency.CompleteAsync(key, result.Value, ct);
                else
                    await idempotency.ReleaseAsync(key, ct); // бизнес-отказ — клиент может повторить
            }

            return result;
        }
        catch
        {
            // Операция не удалась — освобождаем ключ, чтобы клиент мог повторить
            if (key is not null)
                await idempotency.ReleaseAsync(key, ct);
            throw;
        }
    }

    private async Task<Result<PaymentDto>> ChargeAndSaveAsync(
        ProcessPaymentRequest request, Guid userId, CancellationToken ct)
    {
        var course = await db.Courses
            .AsNoTracking()
            .FirstOrDefaultAsync(c => c.Id == request.CourseId && c.Status == CourseStatus.Published, ct);

        if (course is null)
            return Modules.Courses.CourseErrors.NotFound(request.CourseId);

        // Повторная покупка блокируется и для активной, и для завершённой записи;
        // только отозванная (Revoked) запись позволяет купить курс заново
        var alreadyEnrolled = await db.Enrollments.AnyAsync(
            e => e.CourseId == request.CourseId
                 && e.UserId == userId
                 && e.Status != EnrollmentStatus.Revoked, ct);

        if (alreadyEnrolled)
            return BillingErrors.AlreadyEnrolled;

        var payment = Payment.Create(course.Id, userId, course.Price);

        // Имитируем платёжный шлюз. Отказ — ожидаемый исход, а не исключение
        var gateway = await MockPaymentGatewayAsync(course.Price, request.CardToken, ct);
        if (!gateway.Approved)
        {
            payment.Fail(gateway.Reason!);
            db.Payments.Add(payment);
            await db.SaveChangesAsync(ct);

            _payments.Add(1, new KeyValuePair<string, object?>("status", "declined"));
            logger.LogWarning("Payment {PaymentId} declined: {Reason}", payment.Id, gateway.Reason);

            return BillingErrors.Declined(gateway.Reason!);
        }

        payment.Complete(gateway.TransactionId!);

        // Явная транзакция: платёж и запись в outbox фиксируются вместе. SaveChanges и так атомарен,
        // но явная транзакция делает намерение видимым. Провайдер настроен на retry при сбоях
        // соединения (EnableRetryOnFailure), поэтому транзакцию, открытую вручную, нужно выполнять
        // через execution strategy — иначе EF откажется: он не сможет безопасно повторить блок.
        var strategy = db.Database.CreateExecutionStrategy();
        await strategy.ExecuteAsync(async () =>
        {
            await using var tx = await db.Database.BeginTransactionAsync(ct);

            db.Payments.Add(payment);

            // Публикуем событие через Outbox — атомарно с сохранением платежа (Глава 17.5)
            await publishEndpoint.Publish(new PaymentCompleted(
                PaymentId: payment.Id,
                CourseId: course.Id,
                UserId: userId,
                Amount: payment.Amount,
                PaidAt: payment.CompletedAt!.Value), ct);

            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
        });

        _payments.Add(1, new KeyValuePair<string, object?>("status", "completed"));
        logger.LogInformation(
            "Payment {PaymentId} completed: user {UserId} paid {Amount} {Currency} for course {CourseId}",
            payment.Id, userId, payment.Amount, payment.Currency, course.Id);

        return Result.Success(PaymentDto.FromDomain(payment));
    }

    private static async Task<(bool Approved, string? TransactionId, string? Reason)> MockPaymentGatewayAsync(
        decimal amount, string? cardToken, CancellationToken ct)
    {
        // Имитация задержки платёжного шлюза
        await Task.Delay(50, ct);

        // В реальной системе здесь был бы вызов Stripe/PayPal через типизированный HttpClient (Глава 15)
        if (cardToken == "fail_card")
            return (false, null, "Card declined");

        return (true, "txn_" + Guid.NewGuid().ToString("N")[..16], null);
    }

    public async Task<Result<PaymentDto>> GetPaymentAsync(Guid paymentId, Guid userId, CancellationToken ct)
    {
        var payment = await db.Payments.AsNoTracking()
            .FirstOrDefaultAsync(p => p.Id == paymentId && p.UserId == userId, ct);

        return payment is null
            ? BillingErrors.PaymentNotFound(paymentId)
            : Result.Success(PaymentDto.FromDomain(payment));
    }

    public async Task<IReadOnlyList<PaymentDto>> GetUserPaymentsAsync(Guid userId, CancellationToken ct) =>
        await db.Payments.AsNoTracking()
            .Where(p => p.UserId == userId)
            .OrderByDescending(p => p.CreatedAt)
            .Select(p => new PaymentDto(
                p.Id, p.CourseId, p.Amount, p.Currency, p.Status.ToString(),
                p.TransactionId, p.CreatedAt, p.CompletedAt))
            .ToListAsync(ct);
}
