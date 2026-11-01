// MigrationRunner — ядро мигратора: перечисление скриптов, разбиение по GO, журнал dbo.SchemaMigrations.
// Используется Program.cs (CLI) и Waybill.Tests (Testcontainers: поднять SQL Server 2025 в контейнере и применить sql/).
using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;

namespace Waybill.Migrator;

public sealed record MigrationResult(int ExitCode, int Applied, int Skipped, TimeSpan Elapsed, string? FailedScript = null);

public static class MigrationRunner
{
    public static async Task<MigrationResult> RunAsync(MigratorOptions options, TextWriter output, TextWriter error, CancellationToken ct = default)
    {
        var files = Directory.EnumerateFiles(options.SqlRoot, "*.sql", SearchOption.AllDirectories)
            .Select(path => new ScriptFile(path, options.SqlRoot))
            .Where(f => options.Only.Count == 0 || options.Only.Contains(f.Folder, StringComparer.OrdinalIgnoreCase))
            .Where(f => !options.Skip.Contains(f.Folder, StringComparer.OrdinalIgnoreCase))
            .OrderBy(f => f.Folder, StringComparer.Ordinal)
            .ThenBy(f => f.Name, StringComparer.Ordinal)
            .ToList();

        if (files.Count == 0)
        {
            await error.WriteLineAsync($"Нет .sql файлов в {options.SqlRoot}");
            return new MigrationResult(2, 0, 0, TimeSpan.Zero);
        }

        var builder = new SqlConnectionStringBuilder(options.ConnectionString)
        {
            InitialCatalog = "master",
            ApplicationName = "Waybill.Migrator",
        };

        await using var connection = new SqlConnection(builder.ConnectionString);
        connection.InfoMessage += (_, e) => output.WriteLine($"  > {e.Message}");   // PRINT из скриптов
        try
        {
            await connection.OpenAsync(ct);
        }
        catch (SqlException ex)
        {
            await error.WriteLineAsync($"Не удалось подключиться к {builder.DataSource}: {ex.Number} {ex.Message}");
            return new MigrationResult(3, 0, 0, TimeSpan.Zero);
        }

        var applied = await Journal.ReadAppliedAsync(connection, ct);
        var stopwatch = Stopwatch.StartNew();
        var appliedCount = 0;

        foreach (var file in files)
        {
            if (!options.Force && applied.Contains(file.Key))
            {
                await output.WriteLineAsync($"skip    {file.Key}");
                continue;
            }

            var text = await File.ReadAllTextAsync(file.Path, Encoding.UTF8, ct);
            var batches = BatchSplitter.Split(text);
            var index = 0;

            foreach (var batch in batches)
            {
                index++;
                await using var command = new SqlCommand(batch, connection) { CommandTimeout = options.CommandTimeoutSeconds };
                try
                {
                    await command.ExecuteNonQueryAsync(ct);
                }
                catch (SqlException ex)
                {
                    await error.WriteLineAsync($"FAILED  {file.Key} (batch {index}, line {ex.LineNumber}): {ex.Number} {ex.Message}");
                    await error.WriteLineAsync(batch);
                    return new MigrationResult(1, appliedCount, files.Count - appliedCount, stopwatch.Elapsed, file.Key);
                }
            }

            await Journal.RecordAsync(connection, file.Key, SHA256.HashData(Encoding.UTF8.GetBytes(text)), ct);
            await output.WriteLineAsync($"applied {file.Key} ({batches.Count} batches)");
            appliedCount++;
        }

        await output.WriteLineAsync($"done: {appliedCount} applied, {files.Count - appliedCount} skipped, {stopwatch.Elapsed.TotalSeconds:F1}s");
        return new MigrationResult(0, appliedCount, files.Count - appliedCount, stopwatch.Elapsed);
    }
}

public sealed record ScriptFile(string Path, string Root)
{
    public string Folder => new DirectoryInfo(System.IO.Path.GetDirectoryName(Path)!).Name;
    public string Name => System.IO.Path.GetFileName(Path);
    public string Key => $"{Folder}/{Name}";
}

public sealed class MigratorOptions
{
    public string SqlRoot { get; set; } = "sql";
    public string ConnectionString { get; set; } =
        Environment.GetEnvironmentVariable("WAYBILL_CONNECTION")
        ?? "Server=localhost;Integrated Security=true;Encrypt=Mandatory;TrustServerCertificate=true";
    public bool Force { get; set; }
    public int CommandTimeoutSeconds { get; set; } = 600;
    public List<string> Only { get; } = [];
    /// <summary>Папки, которые пропускаются (CI: 16-ops с бэкапами и заданиями Agent применяется отдельно).</summary>
    public List<string> Skip { get; } = [];

    public static MigratorOptions Parse(string[] args)
    {
        var o = new MigratorOptions();
        for (var i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--sql": o.SqlRoot = args[++i]; break;
                case "--connection": o.ConnectionString = args[++i]; break;
                case "--force": o.Force = true; break;
                case "--only": o.Only.AddRange(args[++i].Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)); break;
                case "--skip": o.Skip.AddRange(args[++i].Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)); break;
                case "--timeout": o.CommandTimeoutSeconds = int.Parse(args[++i]); break;
                default: throw new ArgumentException($"Неизвестный аргумент: {args[i]}");
            }
        }
        o.SqlRoot = Path.GetFullPath(o.SqlRoot);
        return o;
    }
}

public static class BatchSplitter
{
    // GO — разделитель клиентского инструмента, не T-SQL. Режем по строкам "GO" / "GO n" (с необязательным комментарием).
    private static readonly Regex GoLine = new(@"^\s*GO(\s+(?<n>\d+))?\s*(--.*)?$", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public static List<string> Split(string text)
    {
        var batches = new List<string>();
        var current = new StringBuilder();

        foreach (var line in text.Split('\n'))
        {
            var trimmed = line.TrimEnd('\r');
            var match = GoLine.Match(trimmed);
            if (match.Success)
            {
                var repeat = match.Groups["n"].Success ? int.Parse(match.Groups["n"].Value) : 1;
                var batch = current.ToString();
                if (!string.IsNullOrWhiteSpace(batch))
                    for (var i = 0; i < repeat; i++) batches.Add(batch);
                current.Clear();
            }
            else
            {
                current.AppendLine(trimmed);
            }
        }

        if (!string.IsNullOrWhiteSpace(current.ToString()))
            batches.Add(current.ToString());

        return batches;
    }
}

internal static class Journal
{
    private const string TableExists =
        "DB_ID(N'Waybill') IS NOT NULL AND OBJECT_ID(N'Waybill.dbo.SchemaMigrations', N'U') IS NOT NULL";

    public static async Task<HashSet<string>> ReadAppliedAsync(SqlConnection connection, CancellationToken ct)
    {
        var applied = new HashSet<string>(StringComparer.Ordinal);
        await using var command = new SqlCommand($"IF {TableExists} SELECT ScriptName FROM Waybill.dbo.SchemaMigrations;", connection);
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
            applied.Add(reader.GetString(0));
        return applied;
    }

    public static async Task RecordAsync(SqlConnection connection, string key, byte[] checksum, CancellationToken ct)
    {
        await using var command = new SqlCommand($"""
            IF {TableExists}
            BEGIN
                UPDATE Waybill.dbo.SchemaMigrations SET AppliedAt = SYSUTCDATETIME(), Checksum = @h WHERE ScriptName = @n;
                IF @@ROWCOUNT = 0 INSERT Waybill.dbo.SchemaMigrations (ScriptName, Checksum) VALUES (@n, @h);
            END
            """, connection);
        command.Parameters.Add("@n", System.Data.SqlDbType.NVarChar, 260).Value = key;
        command.Parameters.Add("@h", System.Data.SqlDbType.VarBinary, 32).Value = checksum;
        await command.ExecuteNonQueryAsync(ct);
    }
}
