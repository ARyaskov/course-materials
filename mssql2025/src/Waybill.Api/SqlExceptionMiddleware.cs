// Единая точка перевода ошибок SQL Server в HTTP (docs/errors.md): номера 50xxx — прикладные, 2627/547 — ограничения, 1205/-2 — нагрузка.
using Microsoft.Data.SqlClient;
using Waybill.Data;

namespace Waybill.Api;

public sealed class SqlExceptionMiddleware(RequestDelegate next, ILogger<SqlExceptionMiddleware> logger)
{
    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await next(context);
        }
        catch (SqlException ex) when (!context.Response.HasStarted)
        {
            var (status, title) = Map(ex);
            if (status >= 500) logger.LogError(ex, "SQL error {Number} on {Path}", ex.Number, context.Request.Path);
            else logger.LogInformation("SQL error {Number} → {Status} on {Path}: {Message}", ex.Number, status, context.Request.Path, ex.Message);

            context.Response.StatusCode = status;
            await context.Response.WriteAsJsonAsync(new
            {
                type = $"https://waybill.example/errors/{ex.Number}",
                title,
                status,
                detail = ex.Message,
                sqlError = ex.Number,
                traceId = context.TraceIdentifier,
            });
        }
    }

    private static (int Status, string Title) Map(SqlException ex) => ex.Number switch
    {
        SqlErrors.NotFound => (404, "Not found"),
        SqlErrors.UnknownCarrier => (404, "Unknown carrier"),
        SqlErrors.UnknownMerchant => (404, "Unknown merchant"),
        SqlErrors.WebhookNotJson => (400, "Body is not JSON"),
        SqlErrors.WebhookBadStructure => (422, "Webhook structure does not match carrier format"),
        SqlErrors.WebhookNoEvents => (422, "Webhook contains no valid events"),
        SqlErrors.BadTrackingFormat => (422, "Tracking number does not match carrier pattern"),
        SqlErrors.VersionConflict => (412, "Precondition failed: the shipment was modified"),
        SqlErrors.AppLockTimeout => (503, "Busy: try again"),
        SqlErrors.UniqueViolation or SqlErrors.UniqueIndexViolation => (409, "Conflict: duplicate key"),
        SqlErrors.ConstraintViolation => (422, "Constraint violation"),
        SqlErrors.Deadlock => (503, "Deadlock: retry the request"),
        SqlErrors.Timeout => (504, "Database timeout"),
        SqlErrors.RlsBlocked => (403, "Forbidden: row belongs to another merchant"),
        SqlErrors.PermissionDenied or SqlErrors.ColumnPermissionDenied => (403, "Forbidden: database permission denied"),
        SqlErrors.BadSortColumn or SqlErrors.BadSortDirection => (400, "Invalid sort parameters"),
        SqlErrors.InvoiceAlreadyIssued or SqlErrors.InvoiceNotDraft => (409, "Invoice is not a draft"),
        >= 50000 => (400, "Application error"),
        _ => (500, "Database error"),
    };
}
