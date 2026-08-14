[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$CleanMmap
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$paths = Get-WindowsPaths -ConfigPath $ConfigPath
$hakoCmd = Join-Path $paths.CoreBin "hako-cmd.exe"
$statePath = Join-Path $paths.StateRoot "hako_drone_service.json"
Set-HakoChildEnvironment -Paths $paths

if (Test-Path -LiteralPath $hakoCmd) {
    & $hakoCmd stop 2>&1 | Out-Host
    & $hakoCmd reset 2>&1 | Out-Host
}

if (Test-Path -LiteralPath $statePath) {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $process = Get-Process -Id $state.pid -ErrorAction SilentlyContinue
    if ($null -ne $process) {
        $actualPath = $process.Path
        $expectedPath = [System.IO.Path]::GetFullPath((Join-Path $paths.SimBin "hako_drone_service.exe"))
        if ([string]::IsNullOrWhiteSpace($actualPath) -or
            -not ([System.IO.Path]::GetFullPath($actualPath)).Equals($expectedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "PID $($state.pid) no longer belongs to the expected hako_drone_service.exe; it was not stopped."
        }
        if (-not $process.WaitForExit(8000)) {
            Stop-Process -Id $process.Id -Force
            Write-Host "Forced stop after timeout: PID $($process.Id)"
        } else {
            Write-Host "Stopped: PID $($process.Id)"
        }
    }
    Remove-Item -LiteralPath $statePath -Force
    Start-Sleep -Milliseconds 1000
}

if ($CleanMmap) {
    Assert-PathIsWorkspaceOwned -Path $paths.MmapRoot -RepositoryRoot $paths.RepositoryRoot
    if (Test-Path -LiteralPath $paths.MmapRoot) {
        Get-ChildItem -LiteralPath $paths.MmapRoot -Force | Remove-Item -Recurse -Force
        Write-Host "Cleaned workspace mmap: $($paths.MmapRoot)"
    }
}

