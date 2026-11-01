<#
.SYNOPSIS
  Контроль дрейфа схемы Waybill: сравнение с последним снимком 'deploy' (ops.usp_DriftCheck, глава 16).

.DESCRIPTION
  Код возврата: 0 — нет отличий, 1 — есть (печатает таблицу), 2 — нет снимка.
  -Snapshot  делает новый снимок с меткой (по умолчанию 'deploy') вместо проверки — вызывается в конце деплоя.

.EXAMPLE
  ./scripts/drift-check.ps1
  ./scripts/drift-check.ps1 -Snapshot
  ./scripts/drift-check.ps1 -Server "localhost,1433" -User sa -Password $env:MSSQL_SA_PASSWORD
#>
[CmdletBinding()]
param(
    [string] $Server = "localhost",
    [string] $User,
    [string] $Password,
    [switch] $Snapshot,
    [string] $Label = "deploy"
)
$ErrorActionPreference = "Stop"
$b = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
$b["Server"] = $Server; $b["Database"] = "Waybill"; $b["Encrypt"] = $true; $b["TrustServerCertificate"] = $true; $b["Application Name"] = "Waybill.DriftCheck"
if ($User) { $b["User ID"] = $User; $b["Password"] = $Password } else { $b["Integrated Security"] = $true }
$conn = New-Object System.Data.SqlClient.SqlConnection($b.ConnectionString)
$conn.add_InfoMessage({ param($s, $e) Write-Host $e.Message -ForegroundColor Yellow })
$conn.Open()

if ($Snapshot) {
    $cmd = $conn.CreateCommand(); $cmd.CommandText = "EXEC ops.usp_SchemaSnapshot @Label = @l;"
    [void]$cmd.Parameters.AddWithValue("@l", $Label); [void]$cmd.ExecuteNonQuery()
    $conn.Close(); exit 0
}

$cmd = $conn.CreateCommand(); $cmd.CommandText = "DECLARE @rc int; EXEC @rc = ops.usp_DriftCheck @BaselineLabel = @l; SELECT @rc AS rc;"
[void]$cmd.Parameters.AddWithValue("@l", $Label)
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$set = New-Object System.Data.DataSet
[void]$adapter.Fill($set)
$rc = 0
foreach ($table in $set.Tables) {
    if ($table.Columns.Contains("rc")) { $rc = [int]$table.Rows[0]["rc"] }
    elseif ($table.Rows.Count -gt 0) { $table | Format-Table -AutoSize | Out-String | Write-Host }
}
$conn.Close()
exit $rc
