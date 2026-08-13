[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$paths = Get-WindowsPaths
$statePath = Join-Path $paths.StateRoot "core-fleet-demo.json"
$hakoCmd = Join-Path $paths.CoreBin "hako-cmd.exe"
Set-HakoChildEnvironment -Paths $paths

if (-not (Test-Path -LiteralPath $statePath)) {
    Write-Host "Core fleet demo is not running."
    exit 0
}
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
& $hakoCmd stop 2>&1 | Out-Host
& $hakoCmd reset 2>&1 | Out-Host

$entries = @(
    @{ Name = "bridge"; Pid = [int]$state.bridgePid; Marker = "pdu_web_bridge.py" },
    @{ Name = "publisher"; Pid = [int]$state.publisherPid; Marker = "core_fleet_state_publisher.py" },
    @{ Name = "conductor"; Pid = [int]$state.conductorPid; Marker = "core_fleet_conductor.py" }
)
if ($state.httpManaged -and $null -ne $state.httpPid) {
    $entries += @{ Name = "http"; Pid = [int]$state.httpPid; Marker = "serve_geo_viewer.py" }
}
foreach ($entry in $entries) {
    $process = Get-Process -Id $entry.Pid -ErrorAction SilentlyContinue
    if ($null -eq $process) { continue }
    $cim = Get-CimInstance Win32_Process -Filter "ProcessId = $($entry.Pid)"
    if ($null -eq $cim -or $cim.CommandLine -notmatch [regex]::Escape($entry.Marker)) {
        throw "PID $($entry.Pid) no longer matches core fleet $($entry.Name); it was not stopped."
    }
    if (-not $process.WaitForExit(5000)) {
        Stop-Process -Id $process.Id -Force
    }
    Write-Host "Stopped core fleet $($entry.Name) PID $($entry.Pid)"
}
if (Test-Path -LiteralPath $state.readyFile) {
    $readyPath = [System.IO.Path]::GetFullPath([string]$state.readyFile)
    Assert-PathIsWorkspaceOwned -Path $readyPath -RepositoryRoot $paths.RepositoryRoot
    Remove-Item -LiteralPath $readyPath -Force
}
Remove-Item -LiteralPath $statePath -Force
