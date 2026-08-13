[CmdletBinding()]
param(
    [string]$ConfigPath,
    [double]$DurationSeconds = 30.0,
    [string]$ExpectedSurface = "wall"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$paths = Get-WindowsPaths -ConfigPath $ConfigPath
Set-HakoChildEnvironment -Paths $paths

$viewerStatePath = Join-Path $paths.StateRoot "phase-w2.json"
if (-not (Test-Path -LiteralPath $viewerStatePath)) {
    throw "Phase W5 viewer state is missing. Run start_web_viewer.ps1 first."
}
$viewerState = Get-Content -LiteralPath $viewerStatePath -Raw | ConvertFrom-Json

$monitorScript = Join-Path $PSScriptRoot "monitor_phase_w5_websocket.py"
$missionScript = Join-Path $PSScriptRoot "run_collision_mission.py"
$pduConfig = Join-Path $paths.ScenarioRoot "config\pdudef\webavatar.json"
$monitorReport = Join-Path $paths.LogsRoot "phase-w5-websocket-collision.json"
$missionReport = Join-Path $paths.LogsRoot "phase-w5-wall-mission.json"
$monitorOut = Join-Path $paths.LogsRoot "phase-w5-monitor.stdout.log"
$monitorErr = Join-Path $paths.LogsRoot "phase-w5-monitor.stderr.log"

foreach ($item in @($monitorScript, $missionScript, $pduConfig)) {
    if (-not (Test-Path -LiteralPath $item)) {
        throw "Phase W5 prerequisite missing: $item"
    }
}

$monitor = Start-Process -FilePath $paths.Python -ArgumentList @(
    $monitorScript,
    "--uri", $viewerState.websocketUri,
    "--duration", $DurationSeconds,
    "--report", $monitorReport,
    "--expect-surface", $ExpectedSurface
) -WorkingDirectory $paths.RepositoryRoot -RedirectStandardOutput $monitorOut `
    -RedirectStandardError $monitorErr -WindowStyle Hidden -PassThru

try {
    Start-Sleep -Milliseconds 750
    & $paths.Python $missionScript --config $pduConfig --report $missionReport
    if ($LASTEXITCODE -ne 0) {
        throw "Collision mission failed with exit code $LASTEXITCODE"
    }

    $monitor.WaitForExit([int](($DurationSeconds + 10.0) * 1000)) | Out-Null
    $monitor.Refresh()
    if (-not $monitor.HasExited) {
        Stop-Process -Id $monitor.Id -Force -ErrorAction SilentlyContinue
        throw "Phase W5 monitor timed out."
    }
    if ($monitor.ExitCode -ne 0) {
        $details = if (Test-Path -LiteralPath $monitorErr) {
            Get-Content -LiteralPath $monitorErr -Raw
        } else {
            "no monitor error log"
        }
        throw "Phase W5 monitor failed with exit code $($monitor.ExitCode): $details"
    }

    Get-Content -LiteralPath $monitorReport -Raw
} finally {
    if (-not $monitor.HasExited) {
        Stop-Process -Id $monitor.Id -Force -ErrorAction SilentlyContinue
    }
}
