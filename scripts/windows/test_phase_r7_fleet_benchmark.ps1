[CmdletBinding()]
param(
    [string]$ReportPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $PSScriptRoot "..\..\runtime\windows\logs\phase-r7-fleet-benchmark-report.json"
}

$superseded = [ordered]@{
    schemaVersion = 1
    measurementKind = "estimated-model"
    estimated = $true
    superseded = $true
    status = "NOT_A_BENCHMARK_RESULT"
    message = "The previous R7 script generated FPS and memory from formulas. Use run_mapray_operations_benchmark.ps1 for actual browser measurements."
    replacement = "scripts/windows/run_mapray_operations_benchmark.ps1"
    timestamp = [DateTime]::UtcNow.ToString("o")
}

$parent = Split-Path -Parent $ReportPath
if (-not [string]::IsNullOrWhiteSpace($parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
}
$superseded | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ReportPath -Encoding utf8
$superseded | ConvertTo-Json -Depth 4
Write-Warning "R7 estimated benchmark is superseded. No PASS/FAIL decision was produced."
