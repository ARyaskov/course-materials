<#
.SYNOPSIS
  Нагрузка «горячие строки»: N параллельных сессий вызывают ops.usp_IngestTrackingEvents с пакетами событий
  для одного и того же отправления (урок 8.10). Печатает время, число deadlock-ов и итоговое число событий.
  Все вставки помечены префиксом ExternalEventId 'hot-<worker>-' и удаляются в конце (-KeepData оставляет).
.EXAMPLE
  ./scripts/hot-rows.ps1 -Workers 8 -Batches 20 -BatchSize 50
#>
[CmdletBinding()]
param(
    [int]    $Workers = 8,
    [int]    $Batches = 20,
    [int]    $BatchSize = 50,
    [string] $Server = "localhost",
    [string] $User,
    [string] $Password,
    [switch] $KeepData
)
$ErrorActionPreference = "Stop"

$b = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
$b["Server"] = $Server; $b["Database"] = "Waybill"; $b["Encrypt"] = $true; $b["TrustServerCertificate"] = $true
$b["Application Name"] = "Waybill.HotRows"; $b["Max Pool Size"] = 64
if ($User) { $b["User ID"] = $User; $b["Password"] = $Password } else { $b["Integrated Security"] = $true }
$cs = $b.ConnectionString

# Пакет для воркера: события с уникальными внешними идентификаторами, все на FX0000000001
$batchSql = @"
DECLARE @batch ops.tt_TrackingEventIn;
INSERT INTO @batch (TrackingNumber, ExternalEventId, ExternalStatus, OccurredAt, LocationText, LocationPostalCode, Description, RawFragment)
SELECT 'FX0000000001', CONCAT('hot-', @worker, '-', @batchNo, '-', v.value),
       CHOOSE(1 + v.value % 3, 'IN_TRANSIT', 'AT_HUB', 'OUT_FOR_DELIVERY'),
       DATEADD(SECOND, @batchNo * 1000 + v.value, '2026-09-02T05:00:00'), N'Москва', '127018', NULL, NULL
FROM GENERATE_SERIES(1, @size) AS v;
EXEC ops.usp_IngestTrackingEvents @CarrierCode = 'FASTEX', @Events = @batch;
"@

$sw = [System.Diagnostics.Stopwatch]::StartNew()

$jobs = 1..$Workers | ForEach-Object {
    $w = $_
    Start-ThreadJob -ArgumentList $cs, $batchSql, $w, $Batches, $BatchSize -ScriptBlock {
        param($cs, $sql, $worker, $batches, $size)
        $conn = New-Object System.Data.SqlClient.SqlConnection($cs); $conn.Open()
        $errors = 0; $retries = 0
        for ($i = 1; $i -le $batches; $i++) {
            $attempt = 0
            while ($true) {
                try {
                    $cmd = $conn.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = 60
                    [void]$cmd.Parameters.AddWithValue("@worker", $worker)
                    [void]$cmd.Parameters.AddWithValue("@batchNo", $i)
                    [void]$cmd.Parameters.AddWithValue("@size", $size)
                    [void]$cmd.ExecuteNonQuery(); break
                } catch {
                    if ($_.Exception.InnerException.Number -eq 1205 -and $attempt -lt 3) { $attempt++; $retries++; Start-Sleep -Milliseconds (50 * $attempt); continue }
                    $errors++; break
                }
            }
        }
        $conn.Close()
        [pscustomobject]@{ Worker = $worker; Errors = $errors; Retries = $retries }
    }
}
$results = $jobs | Receive-Job -Wait -AutoRemoveJob
$sw.Stop()

$results | Format-Table -AutoSize
$total = $Workers * $Batches * $BatchSize
Write-Host ("{0} events in {1:N1}s = {2:N0} events/s; retries after deadlock: {3}" -f $total, $sw.Elapsed.TotalSeconds, ($total / $sw.Elapsed.TotalSeconds), ($results | Measure-Object Retries -Sum).Sum) -ForegroundColor Cyan

& "$PSScriptRoot/query.ps1" -Server $Server "SELECT COUNT(*) AS hot_events FROM ship.TrackingEvent WHERE ExternalEventId LIKE 'hot-%'; SELECT wait_type, waiting_tasks_count, wait_time_ms FROM sys.dm_os_wait_stats WHERE wait_type IN (N'LCK_M_X', N'LCK_M_U', N'LCK_M_S', N'PAGELATCH_EX') ORDER BY wait_time_ms DESC;"

if (-not $KeepData) {
    & "$PSScriptRoot/query.ps1" -Server $Server "DELETE FROM ship.TrackingEvent WHERE ExternalEventId LIKE 'hot-%'; DELETE FROM ops.Outbox WHERE Topic = 'shipment.status-changed' AND JSON_VALUE(Payload, '$.tracking') = 'FX0000000001' AND CreatedAt > DATEADD(MINUTE, -30, SYSUTCDATETIME());"
    Write-Host "hot-* events removed" -ForegroundColor DarkGray
}
