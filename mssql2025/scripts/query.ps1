<#
.SYNOPSIS
  Выполняет запрос к базе Waybill и печатает результат таблицей (замена sqlcmd -Q на стенде без sqlcmd).
.EXAMPLE
  ./scripts/query.ps1 "SELECT name, compatibility_level FROM sys.databases"
  ./scripts/query.ps1 -File ./sql/09-performance/030_sla_report_before_after.sql
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)] [string] $Query,
    [string] $File,
    [string] $Server = "localhost",
    [string] $Database = "Waybill",
    [string] $User,
    [string] $Password
)
$ErrorActionPreference = "Stop"
if ($File) { $Query = Get-Content -Raw -Encoding UTF8 $File }

$b = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
$b["Server"] = $Server; $b["Database"] = $Database; $b["Encrypt"] = $true; $b["TrustServerCertificate"] = $true
$b["Application Name"] = "Waybill.Query"
if ($User) { $b["User ID"] = $User; $b["Password"] = $Password } else { $b["Integrated Security"] = $true }

$conn = New-Object System.Data.SqlClient.SqlConnection($b.ConnectionString)
$conn.add_InfoMessage({ param($s, $e) Write-Host $e.Message -ForegroundColor Yellow })   # PRINT / RAISERROR(...,0,1)
$conn.Open()
try {
    foreach ($batch in ($Query -split "(?m)^\s*GO\s*$")) {
        if (-not $batch.Trim()) { continue }
        $cmd = $conn.CreateCommand(); $cmd.CommandText = $batch; $cmd.CommandTimeout = 600
        $da = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
        $ds = New-Object System.Data.DataSet
        [void]$da.Fill($ds)
        foreach ($t in $ds.Tables) { $t | Format-Table -AutoSize | Out-String -Width 4096 | Write-Host }
    }
}
finally { $conn.Close() }
