<#
.SYNOPSIS
  tSQLt для Waybill: установка фреймворка и запуск тестов из tests/tsqlt.

.DESCRIPTION
  -Install  скачивает tSQLt (https://tsqlt.org/download/tsqlt/) в scratch-папку, выполняет PrepareServer.sql (включает CLR,
            требует sysadmin) и tSQLt.class.sql в базе Waybill. Повторный вызов переустанавливает.
  Без ключей: применяет tests/tsqlt/*.sql (классы тестов) и выполняет tSQLt.RunAll; результат — в формате JUnit (tests/tsqlt/results.xml)
  для CI и код возврата 1 при упавших тестах.

.EXAMPLE
  ./scripts/tsqlt.ps1 -Install
  ./scripts/tsqlt.ps1
  ./scripts/tsqlt.ps1 -Server "localhost,1433" -User sa -Password $env:MSSQL_SA_PASSWORD
#>
[CmdletBinding()]
param(
    [string] $Server = "localhost",
    [string] $User,
    [string] $Password,
    [switch] $Install,
    [string] $TestsDir = (Join-Path $PSScriptRoot "..\tests\tsqlt"),
    [string] $TsqltUrl = "https://tsqlt.org/download/tsqlt/"
)
$ErrorActionPreference = "Stop"

function New-Connection([string]$database) {
    $b = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $b["Server"] = $Server; $b["Database"] = $database; $b["Encrypt"] = $true; $b["TrustServerCertificate"] = $true
    $b["Application Name"] = "Waybill.tSQLt"
    if ($User) { $b["User ID"] = $User; $b["Password"] = $Password } else { $b["Integrated Security"] = $true }
    $c = New-Object System.Data.SqlClient.SqlConnection($b.ConnectionString)
    $c.add_InfoMessage({ param($s, $e) Write-Host "  > $($e.Message)" -ForegroundColor Yellow })
    $c.Open(); return $c
}

function Invoke-SqlFile($conn, [string]$path) {
    $text = Get-Content -Raw -Encoding UTF8 $path
    $batches = ($text -split "(?m)^\s*GO\s*$") | Where-Object { $_.Trim() }
    foreach ($batch in $batches) {
        $cmd = $conn.CreateCommand(); $cmd.CommandText = $batch; $cmd.CommandTimeout = 600
        [void]$cmd.ExecuteNonQuery()
    }
}

if ($Install) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "tsqlt"
    New-Item -ItemType Directory -Force $tmp | Out-Null
    $zip = Join-Path $tmp "tSQLt.zip"
    Write-Host "Скачиваем tSQLt из $TsqltUrl"
    Invoke-WebRequest -Uri $TsqltUrl -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $prepare = Get-ChildItem $tmp -Recurse -Filter "PrepareServer.sql" | Select-Object -First 1
    $class   = Get-ChildItem $tmp -Recurse -Filter "tSQLt.class.sql"  | Select-Object -First 1
    if (-not $class) { throw "tSQLt.class.sql не найден в архиве" }
    $master = New-Connection "master"
    if ($prepare) { Write-Host "PrepareServer.sql (CLR)"; Invoke-SqlFile $master $prepare.FullName }
    $master.Close()
    $db = New-Connection "Waybill"
    Write-Host "tSQLt.class.sql → Waybill"; Invoke-SqlFile $db $class.FullName
    $db.Close()
    Write-Host "tSQLt установлен" -ForegroundColor Green
    return
}

$conn = New-Connection "Waybill"
foreach ($f in Get-ChildItem $TestsDir -Filter "*.sql" | Sort-Object Name) {
    Write-Host "== $($f.Name)"
    Invoke-SqlFile $conn $f.FullName
}
$run = $conn.CreateCommand(); $run.CommandText = "EXEC tSQLt.RunAll;"; $run.CommandTimeout = 600
try { [void]$run.ExecuteNonQuery() } catch { Write-Host $_.Exception.Message -ForegroundColor Red }

$xml = $conn.CreateCommand(); $xml.CommandText = "EXEC tSQLt.XmlResultFormatter;"
$result = [string]$xml.ExecuteScalar()
$out = Join-Path $TestsDir "results.xml"
Set-Content -Path $out -Value $result -Encoding UTF8
$failed = $conn.CreateCommand(); $failed.CommandText = "SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result <> 'Success';"
$n = [int]$failed.ExecuteScalar()
$conn.Close()
Write-Host "результаты: $out; упавших: $n" -ForegroundColor ($(if ($n -eq 0) { "Green" } else { "Red" }))
exit $(if ($n -eq 0) { 0 } else { 1 })
