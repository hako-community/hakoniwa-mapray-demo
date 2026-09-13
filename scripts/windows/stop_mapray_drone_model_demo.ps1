[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$paths = Get-WindowsPaths
$stateFile = Join-Path $paths.StateRoot "mapray-drone-model-http.json"
if (-not (Test-Path -LiteralPath $stateFile -PathType Leaf)) {
    Write-Host "Mapray drone model demo is not running from its launcher."
    exit 0
}

$state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
if ($state.purpose -ne "mapray-drone-model") {
    throw "State file does not belong to the Mapray drone model demo."
}
$pidValue = [int]$state.pid
$proc = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
if ($null -ne $proc) {
    if ($proc.ProcessName -notlike "python*") {
        throw "PID $pidValue is not a Python process; it was not stopped."
    }
    if ($state.PSObject.Properties.Name -contains "processStartTimeUtc") {
        $actualStart = $proc.StartTime.ToUniversalTime()
        $expectedStart = if ($state.processStartTimeUtc -is [DateTime]) {
            $state.processStartTimeUtc.ToUniversalTime()
        } else {
            [DateTimeOffset]::Parse([string]$state.processStartTimeUtc).UtcDateTime
        }
        if ([Math]::Abs(($actualStart - $expectedStart).TotalSeconds) -gt 1) {
            throw "PID $pidValue was reused by another process; it was not stopped."
        }
    }
    Stop-Process -Id $pidValue -Force
    Write-Host "Stopped Mapray drone model demo HTTP server PID $pidValue"
}
Remove-Item -LiteralPath $stateFile -Force
