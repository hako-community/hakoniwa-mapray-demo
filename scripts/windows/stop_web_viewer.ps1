[CmdletBinding()]
param(
    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$paths = Get-WindowsPaths -ConfigPath $ConfigPath
$statePath = Join-Path $paths.StateRoot "phase-w2.json"
if (-not (Test-Path -LiteralPath $statePath)) {
    Write-Host "Phase W2 is not running."
    exit 0
}
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$httpMarker = if ($state.PSObject.Properties.Name -contains "httpServerScript") {
    "serve_geo_viewer.py"
} else {
    "-m http.server"
}
foreach ($entry in @(
    @{ Name = "bridge"; Pid = [int]$state.bridgePid; Marker = "pdu_web_bridge.py" },
    @{ Name = "http"; Pid = [int]$state.httpPid; Marker = $httpMarker }
)) {
    $proc = Get-Process -Id $entry.Pid -ErrorAction SilentlyContinue
    if ($null -eq $proc) { continue }
    $cim = Get-CimInstance Win32_Process -Filter "ProcessId = $($entry.Pid)"
    if ($null -eq $cim -or $cim.CommandLine -notmatch [regex]::Escape($entry.Marker)) {
        throw "PID $($entry.Pid) no longer matches Phase W2 $($entry.Name) process; it was not stopped."
    }
    Stop-Process -Id $entry.Pid -Force
    Write-Host "Stopped Phase W2 $($entry.Name) PID $($entry.Pid)"
}
Remove-Item -LiteralPath $statePath -Force
