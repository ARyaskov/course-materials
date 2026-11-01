<#
.SYNOPSIS
  Применяет SQL-скрипты проекта Waybill к экземпляру SQL Server 2025 в лексикографическом порядке.

.DESCRIPTION
  - Не требует sqlcmd: использует System.Data.SqlClient из pwsh.
  - Разбивает файлы на пакеты по строкам GO (как sqlcmd), выполняет пакеты по очереди.
  - Ведёт журнал dbo.SchemaMigrations в базе Waybill: применённые скрипты пропускаются,
    пока не указан -Force (повторное применение безопасно — скрипты идемпотентны).
  - Ошибка в любом пакете останавливает выполнение и печатает файл/пакет.

.EXAMPLE
  ./scripts/apply.ps1                                # локальный экземпляр, Windows-аутентификация
  ./scripts/apply.ps1 -Server "localhost,1433" -User sa -Password $env:MSSQL_SA_PASSWORD
  ./scripts/apply.ps1 -Only 01-start,03-schema      # только выбранные главы
  ./scripts/apply.ps1 -Force                         # переприменить всё
#>
[CmdletBinding()]
param(
    [string]   $Server   = "localhost",
    [string]   $User,
    [string]   $Password,
    [string[]] $Only,
    [switch]   $Force,
    [string]   $SqlRoot  = (Join-Path $PSScriptRoot "..\sql")
)

$ErrorActionPreference = "Stop"

function New-Connection([string]$database) {
    $b = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $b["Server"] = $Server
    $b["Database"] = $database
    $b["Encrypt"] = $true
    $b["TrustServerCertificate"] = $true
    $b["Application Name"] = "Waybill.Apply"
    if ($User) { $b["User ID"] = $User; $b["Password"] = $Password }
    else       { $b["Integrated Security"] = $true }
    $c = New-Object System.Data.SqlClient.SqlConnection($b.ConnectionString)
    $c.add_InfoMessage({ param($s, $e) Write-Host "  > $($e.Message)" -ForegroundColor Yellow })
    $c.Open()
    return $c
}

function Split-Batches([string]$text) {
    # GO — разделитель клиентского инструмента, не T-SQL: режем по строкам "GO" / "GO n".
    $batches = New-Object System.Collections.Generic.List[string]
    $sb = New-Object System.Text.StringBuilder
    foreach ($line in ($text -split "`r?`n")) {
        if ($line -match '^\s*GO(\s+(?<n>\d+))?\s*(--.*)?$') {
            $n = if ($Matches.n) { [int]$Matches.n } else { 1 }
            $batch = $sb.ToString()
            if ($batch.Trim()) { for ($i = 0; $i -lt $n; $i++) { $batches.Add($batch) } }
            [void]$sb.Clear()
        } else {
            [void]$sb.AppendLine($line)
        }
    }
    if ($sb.ToString().Trim()) { $batches.Add($sb.ToString()) }
    return $batches
}

function Get-Applied($conn) {
    $applied = New-Object System.Collections.Generic.HashSet[string]
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "IF DB_ID(N'Waybill') IS NOT NULL AND OBJECT_ID(N'Waybill.dbo.SchemaMigrations', N'U') IS NOT NULL
                        SELECT ScriptName FROM Waybill.dbo.SchemaMigrations;"
    $r = $cmd.ExecuteReader()
    while ($r.Read()) { [void]$applied.Add($r.GetString(0)) }
    $r.Close()
    return ,$applied   # запятая: пустой HashSet иначе разворачивается в $null
}

$files = Get-ChildItem -Path $SqlRoot -Recurse -Filter *.sql |
         Where-Object { -not $Only -or ($Only -contains $_.Directory.Name) } |
         Sort-Object { $_.Directory.Name }, { $_.Name }

$conn = New-Connection "master"
try {
    $applied = Get-Applied $conn
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    foreach ($f in $files) {
        $key = "$($f.Directory.Name)/$($f.Name)"
        if (-not $Force -and $applied.Contains($key)) { Write-Host "skip    $key" -ForegroundColor DarkGray; continue }

        $text = Get-Content -Raw -Encoding UTF8 $f.FullName
        $i = 0
        foreach ($batch in (Split-Batches $text)) {
            $i++
            $cmd = $conn.CreateCommand()
            $cmd.CommandTimeout = 600
            $cmd.CommandText = $batch
            try { [void]$cmd.ExecuteNonQuery() }
            catch {
                Write-Host "FAILED  $key (batch $i)" -ForegroundColor Red
                Write-Host $batch
                throw
            }
        }

        # Журнал: пишем в Waybill, если база и таблица уже существуют (после 002_schemas.sql).
        $hash = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($text))
        $log = $conn.CreateCommand()
        $log.CommandText = "IF DB_ID(N'Waybill') IS NOT NULL AND OBJECT_ID(N'Waybill.dbo.SchemaMigrations', N'U') IS NOT NULL
            BEGIN
                UPDATE Waybill.dbo.SchemaMigrations SET AppliedAt = SYSUTCDATETIME(), Checksum = @h WHERE ScriptName = @n;
                IF @@ROWCOUNT = 0 INSERT Waybill.dbo.SchemaMigrations (ScriptName, Checksum) VALUES (@n, @h);
            END"
        $pn = $log.Parameters.Add("@n", [System.Data.SqlDbType]::NVarChar, 260); $pn.Value = $key
        $ph = $log.Parameters.Add("@h", [System.Data.SqlDbType]::VarBinary, 32); $ph.Value = $hash
        [void]$log.ExecuteNonQuery()
        Write-Host "applied $key ($i batches)" -ForegroundColor Green
    }
    Write-Host "done in $([int]$sw.Elapsed.TotalSeconds)s" -ForegroundColor Cyan
}
finally { $conn.Close() }
