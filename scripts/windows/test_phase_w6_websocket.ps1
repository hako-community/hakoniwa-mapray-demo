[CmdletBinding()]
param(
    [string]$ConfigPath,
    [double]$DurationSeconds = 25.0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$fanoutProbe = Join-Path $PSScriptRoot "probe_websocket_fanout.py"

$paths = Get-WindowsPaths -ConfigPath $ConfigPath
Set-HakoChildEnvironment -Paths $paths

$viewerStatePath = Join-Path $paths.StateRoot "phase-w2.json"
if (-not (Test-Path -LiteralPath $viewerStatePath)) {
    throw "Phase W6 viewer state is missing. Run start_web_viewer.ps1 first."
}
$viewerState = Get-Content -LiteralPath $viewerStatePath -Raw | ConvertFrom-Json

if (-not (Test-Path -LiteralPath $fanoutProbe)) {
    throw "Phase W6 WebSocket fan-out probe is missing: $fanoutProbe"
}
& $paths.Python $fanoutProbe --uri $viewerState.websocketUri --clients 2 --timeout 5
if ($LASTEXITCODE -ne 0) {
    throw "Phase W6 WebSocket fan-out probe failed with exit code $LASTEXITCODE"
}

$monitorScript = Join-Path $PSScriptRoot "monitor_phase_w5_websocket.py"
$missionScript = Join-Path $PSScriptRoot "run_collision_mission.py"
$pduConfig = Join-Path $paths.ScenarioRoot "config\pdudef\webavatar.json"
$terrainManifestPath = Join-Path $paths.RuntimeRoot "generated\shibuya\terrain-manifest.json"
$terrainGridPath = Join-Path $paths.GeoViewerRoot "config\terrain-grid.json"
$monitorReport = Join-Path $paths.LogsRoot "phase-w6-websocket-ground.json"
$missionReport = Join-Path $paths.LogsRoot "phase-w6-websocket-mission.json"
$monitorOut = Join-Path $paths.LogsRoot "phase-w6-websocket.stdout.log"
$monitorErr = Join-Path $paths.LogsRoot "phase-w6-websocket.stderr.log"

foreach ($item in @($monitorScript, $missionScript, $pduConfig, $terrainManifestPath, $terrainGridPath)) {
    if (-not (Test-Path -LiteralPath $item)) {
        throw "Phase W6 prerequisite missing: $item"
    }
}

$terrainManifest = Get-Content -LiteralPath $terrainManifestPath -Raw | ConvertFrom-Json
$centerSample = $terrainManifest.mujoco_validation.samples |
    Where-Object { [double]$_.x_m -eq 0.0 -and [double]$_.y_m -eq 0.0 } |
    Select-Object -First 1
if ($null -eq $centerSample) {
    throw "Terrain manifest contains no center MuJoCo sample."
}
$terrainHeight = [double]$centerSample.expected_height_m

$monitor = Start-Process -FilePath $paths.Python -ArgumentList @(
    $monitorScript,
    "--uri", $viewerState.websocketUri,
    "--duration", $DurationSeconds,
    "--report", $monitorReport,
    "--expect-surface", "ground",
    "--terrain-grid", $terrainGridPath
) -WorkingDirectory $paths.RepositoryRoot -RedirectStandardOutput $monitorOut `
    -RedirectStandardError $monitorErr -WindowStyle Hidden -PassThru

try {
    Start-Sleep -Milliseconds 750
    & $paths.Python $missionScript `
        --config $pduConfig `
        --report $missionReport `
        --takeoff-height ($terrainHeight + 5.0) `
        --target-x 0 `
        --target-y 0 `
        --target-z ($terrainHeight - 2.0) `
        --speed 2 `
        --move-timeout 15
    if ($LASTEXITCODE -ne 0) {
        throw "Phase W6 WebSocket mission failed with exit code $LASTEXITCODE"
    }

    $monitor.WaitForExit([int](($DurationSeconds + 10.0) * 1000)) | Out-Null
    $monitor.Refresh()
    if (-not $monitor.HasExited) {
        Stop-Process -Id $monitor.Id -Force -ErrorAction SilentlyContinue
        throw "Phase W6 WebSocket monitor timed out."
    }
    if ($monitor.ExitCode -ne 0) {
        $details = if (Test-Path -LiteralPath $monitorErr) {
            Get-Content -LiteralPath $monitorErr -Raw
        } else {
            "no monitor error log"
        }
        throw "Phase W6 WebSocket monitor failed with exit code $($monitor.ExitCode): $details"
    }

    Get-Content -LiteralPath $monitorReport -Raw
} finally {
    if (-not $monitor.HasExited) {
        Stop-Process -Id $monitor.Id -Force -ErrorAction SilentlyContinue
    }
}
