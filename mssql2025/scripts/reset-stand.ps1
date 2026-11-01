<#
.SYNOPSIS
  Воспроизводимый стенд Waybill с нуля (глава 16): DROP DATABASE → apply всех глав → тесты .NET → tSQLt → снимок дрейфа.

.DESCRIPTION
  Необратимо удаляет базу Waybill на указанном экземпляре (требует -Confirm:$false или ключ -Force).
  Задания Agent категории Waybill и серверные объекты (аудит, сертификат TDE, логины) не трогает — скрипты идемпотентны.
  Печатает длительность каждого шага; код возврата ≠ 0 при первой ошибке.

.EXAMPLE
  ./scripts/reset-stand.ps1 -Force
  ./scripts/reset-stand.ps1 -Force -Server "localhost,1433" -User sa -Password $env:MSSQL_SA_PASSWORD -SkipTsqlt
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $Server = "localhost",
    [string] $User,
    [string] $Password,
    [switch] $Force,
    [switch] $SkipTests,
    [switch] $SkipTsqlt
)
$ErrorActionPreference = "Stop"
$root = Join-Path $PSScriptRoot ".."
$auth = @{}; if ($User) { $auth.User = $User; $auth.Password = $Password }   # хэш-таблица для splatting: пустой массив схлопывается в $null

if (-not $Force -and -not $PSCmdlet.ShouldProcess("Waybill @ $Server", "DROP DATABASE")) { return }

$sw = [Diagnostics.Stopwatch]::StartNew()
function Step([string]$name, [scriptblock]$body) {
    $t = [Diagnostics.Stopwatch]::StartNew()
    Write-Host "== $name" -ForegroundColor Cyan
    & $body
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "${name}: exit $LASTEXITCODE" }
    Write-Host "   ${name}: $([int]$t.Elapsed.TotalSeconds)s" -ForegroundColor DarkGray
}

Step "drop database" {
    & (Join-Path $PSScriptRoot "query.ps1") -Server $Server -Database master @auth -Query @"
IF DB_ID(N'Waybill') IS NOT NULL
BEGIN
    ALTER DATABASE Waybill SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE Waybill;
END
"@
}
Step "apply sql/**" { & (Join-Path $PSScriptRoot "apply.ps1") -Server $Server @auth -Force }
if (-not $SkipTests) {
    Step "dotnet test" {
        $env:WAYBILL_CONNECTION = if ($User) { "Server=$Server;Database=Waybill;User ID=$User;Password=$Password;Encrypt=Mandatory;TrustServerCertificate=true" }
                                  else      { "Server=$Server;Database=Waybill;Integrated Security=true;Encrypt=Mandatory;TrustServerCertificate=true" }
        dotnet test (Join-Path $root "tests/Waybill.Tests") --nologo -v q
    }
}
if (-not $SkipTsqlt) {
    Step "tSQLt" {
        & (Join-Path $PSScriptRoot "tsqlt.ps1") -Install -Server $Server @auth
        & (Join-Path $PSScriptRoot "tsqlt.ps1") -Server $Server @auth
    }
}
Step "drift snapshot" { & (Join-Path $PSScriptRoot "drift-check.ps1") -Server $Server @auth -Snapshot }
Write-Host "стенд пересоздан за $([int]$sw.Elapsed.TotalSeconds)s" -ForegroundColor Green
