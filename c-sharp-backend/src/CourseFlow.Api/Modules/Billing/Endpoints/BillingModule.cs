using CourseFlow.Api.Common.Auth;
using CourseFlow.Api.Common.Errors;
using CourseFlow.Api.Common.Validation;
using CourseFlow.Api.Modules.Billing.Services;
using Microsoft.AspNetCore.Mvc;

namespace CourseFlow.Api.Modules.Billing.Endpoints;

public static class BillingModule
{
    public static IServiceCollection AddBillingModule(this IServiceCollection services)
    {
        services.AddScoped<BillingService>();
        return services;
    }

    public static IEndpointRouteBuilder MapBilling(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/v1/billing")
            .RequireAuthorization()
            .WithTags("Billing");

        group.MapPost("/payments", ProcessPaymentAsync)
            .WithValidation<ProcessPaymentRequest>()
            .Produces<PaymentDto>(StatusCodes.Status201Created)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status422UnprocessableEntity);

        group.MapGet("/payments/{paymentId:guid}", GetPaymentAsync)
            .Produces<PaymentDto>()
            .ProducesProblem(StatusCodes.Status404NotFound);

        group.MapGet("/payments", GetMyPaymentsAsync).Produces<IReadOnlyList<PaymentDto>>();

        return app;
    }

    private static async Task<IResult> ProcessPaymentAsync(
        ProcessPaymentRequest request,
        [FromHeader(Name = "Idempotency-Key")] string? idempotencyKey,
        BillingService service,
        ICurrentUser currentUser,
        CancellationToken ct)
    {
        // UserId берём из токена, а не из тела запроса: пользователь не может
        // инициировать платёж от чужого имени
        var result = await service.ProcessPaymentAsync(request, currentUser.RequiredUserId(), idempotencyKey, ct);
        return result.ToHttpResult(p => Results.Created($"/api/v1/billing/payments/{p.Id}", p));
    }

    private static async Task<IResult> GetPaymentAsync(
        Guid paymentId, BillingService service, ICurrentUser currentUser, CancellationToken ct)
    {
        var result = await service.GetPaymentAsync(paymentId, currentUser.RequiredUserId(), ct);
        return result.ToHttpResult(Results.Ok);
    }

    private static async Task<IResult> GetMyPaymentsAsync(
        BillingService service, ICurrentUser currentUser, CancellationToken ct) =>
        Results.Ok(await service.GetUserPaymentsAsync(currentUser.RequiredUserId(), ct));
}
