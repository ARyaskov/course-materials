// Счета (глава 17): генерация черновика, выставление, отчёт — всё в процедурах bill.*; арендатор — через SESSION_CONTEXT (RLS).
using System.Data;
using Dapper;

namespace Waybill.Data.Repositories;

public sealed class InvoiceRepository(IDbConnectionFactory db)
{
    public async Task<InvoiceHeader> GenerateAsync(int merchantId, DateOnly month, string user, CancellationToken ct)
    {
        await using var conn = await db.OpenAsync(user, merchantId, ct);
        return await conn.QuerySingleAsync<InvoiceHeader>(new CommandDefinition("bill.usp_GenerateInvoice",
            new { MerchantId = merchantId, Month = month.ToDateTime(TimeOnly.MinValue) },
            commandType: CommandType.StoredProcedure, commandTimeout: db.CommandTimeout, cancellationToken: ct));
    }

    public async Task IssueAsync(int merchantId, long invoiceId, string user, CancellationToken ct)
    {
        await using var conn = await db.OpenAsync(user, merchantId, ct);
        await conn.ExecuteAsync(new CommandDefinition("bill.usp_IssueInvoice", new { InvoiceId = invoiceId },
            commandType: CommandType.StoredProcedure, cancellationToken: ct));
    }

    /// <summary>Два набора: заголовок (0..1 строк) и разбивка по перевозчику/региону.</summary>
    public async Task<InvoiceReport> ReportAsync(int merchantId, DateOnly month, CancellationToken ct)
    {
        await using var conn = await db.OpenAsync(null, merchantId, ct);
        using var grid = await conn.QueryMultipleAsync(new CommandDefinition("bill.usp_InvoiceReport",
            new { MerchantId = merchantId, Month = month.ToDateTime(TimeOnly.MinValue) },
            commandType: CommandType.StoredProcedure, cancellationToken: ct));
        var header = await grid.ReadSingleOrDefaultAsync<InvoiceHeader>();
        var lines = (await grid.ReadAsync<InvoiceReportLine>()).AsList();
        return new InvoiceReport(header, lines);
    }
}
