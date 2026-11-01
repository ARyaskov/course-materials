// JSON между SQL Server 2025 (тип json) и .NET: Dapper TypeHandler для JsonDocument и явный SqlDbType.Json для параметров.
using System.Data;
using System.Text.Json;
using Dapper;
using Microsoft.Data.SqlClient;

namespace Waybill.Data;

/// <summary>Dapper читает json-столбец как строку; TypeHandler превращает её в JsonDocument и обратно.</summary>
public sealed class JsonDocumentHandler : SqlMapper.TypeHandler<JsonDocument?>
{
    public static readonly JsonDocumentHandler Instance = new();

    public override JsonDocument? Parse(object value) =>
        value is null or DBNull ? null : JsonDocument.Parse((string)value);

    public override void SetValue(IDbDataParameter parameter, JsonDocument? value)
    {
        if (parameter is SqlParameter sp) sp.SqlDbType = SqlDbType.Json;        // SqlClient 6.x: нативный json, не nvarchar
        parameter.Value = value is null ? DBNull.Value : value.RootElement.GetRawText();
    }
}

public static class JsonParameters
{
    /// <summary>Параметр типа json из готовой строки (тело webhook-а, патч атрибутов).</summary>
    public static SqlParameter Json(string name, string? json) =>
        new(name, SqlDbType.Json) { Value = (object?)json ?? DBNull.Value };

    public static void Register()
    {
        SqlMapper.AddTypeHandler(JsonDocumentHandler.Instance);
    }
}
