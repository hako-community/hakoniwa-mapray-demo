[CmdletBinding()]
param(
    [string]$ConfigPath,
    [double]$MonitorDurationSeconds = 25.0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$paths = Get-WindowsPaths -ConfigPath $ConfigPath
Set-HakoChildEnvironment -Paths $paths

$monitorScript = Join-Path $PSScriptRoot "monitor_phase_w1.py"
$missionScript = Join-Path $PSScriptRoot "run_collision_mission.py"
$pduConfig = Join-Path $paths.ScenarioRoot "config\pdudef\webavatar.json"
$terrainManifestPath = Join-Path $paths.RuntimeRoot "generated\shibuya\terrain-manifest.json"
$monitorReport = Join-Path $paths.LogsRoot "phase-w6-terrain-monitor.json"
$missionReport = Join-Path $paths.LogsRoot "phase-w6-terrain-mission.json"
$resultPath = Join-Path $paths.LogsRoot "phase-w6-terrain-runtime.json"
$monitorOut = Join-Path $paths.LogsRoot "phase-w6-terrain-monitor.stdout.log"
$monitorErr = Join-Path $paths.LogsRoot "phase-w6-terrain-monitor.stderr.log"

foreach ($item in @($monitorScript, $missionScript, $pduConfig, $terrainManifestPath)) {
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
$takeoffHeight = $terrainHeight + 5.0
$penetratingTargetHeight = $terrainHeight - 2.0

$monitor = Start-Process -FilePath $paths.Python -ArgumentList @(
    $monitorScript,
    "--config", $pduConfig,
    "--duration", $MonitorDurationSeconds,
    "--interval", "0.005",
    "--report", $monitorReport
) -WorkingDirectory $paths.RepositoryRoot -RedirectStandardOutput $monitorOut `
    -RedirectStandardError $monitorErr -WindowStyle Hidden -PassThru

try {
    Start-Sleep -Milliseconds 750
    & $paths.Python $missionScript `
        --config $pduConfig `
        --report $missionReport `
        --takeoff-height $takeoffHeight `
        --target-x 0 `
        --target-y 0 `
        --target-z $penetratingTargetHeight `
        --speed 2 `
        --move-timeout 15
    if ($LASTEXITCODE -ne 0) {
        throw "Phase W6 terrain mission failed with exit code $LASTEXITCODE"
    }

    $monitor.WaitForExit([int](($MonitorDurationSeconds + 10.0) * 1000)) | Out-Null
    $monitor.Refresh()
    if (-not $monitor.HasExited) {
        Stop-Process -Id $monitor.Id -Force -ErrorAction SilentlyContinue
        throw "Phase W6 monitor timed out."
    }
    if ($monitor.ExitCode -ne 0) {
        throw "Phase W6 monitor failed with exit code $($monitor.ExitCode)."
    }

    $monitorData = Get-Content -LiteralPath $monitorReport -Raw | ConvertFrom-Json
    $missionData = Get-Content -LiteralPath $missionReport -Raw | ConvertFrom-Json
    $finalHeight = [double]$missionData.afterMove.position.z
    $heightAboveTerrain = $finalHeight - $terrainHeight
    $collisionIncrease = [int]$monitorData.collidedCountIncrease
    $terrainStoppedDescent = (
        $finalHeight -gt $penetratingTargetHeight + 1.0 -and
        $heightAboveTerrain -ge -0.05 -and
        $heightAboveTerrain -le 0.75
    )
    $passed = (
        [bool]$missionData.takeoffSucceeded -and
        $collisionIncrease -gt 0 -and
        $terrainStoppedDescent
    )
    $result = [ordered]@{
        generatedAt = (Get-Date).ToString("o")
        passed = $passed
        terrainHeightM = $terrainHeight
        takeoffHeightM = $takeoffHeight
        penetratingTargetHeightM = $penetratingTargetHeight
        finalHeightM = $finalHeight
        heightAboveTerrainM = $heightAboveTerrain
        collidedCountIncrease = $collisionIncrease
        terrainStoppedDescent = $terrainStoppedDescent
        moveSucceeded = [bool]$missionData.moveSucceeded
        monitorReport = $monitorReport
        missionReport = $missionReport
    }
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resultPath -Encoding utf8
    $result | ConvertTo-Json -Depth 6
    if (-not $passed) {
        throw "Phase W6 terrain collision validation failed. See $resultPath"
    }
} finally {
    if (-not $monitor.HasExited) {
        Stop-Process -Id $monitor.Id -Force -ErrorAction SilentlyContinue
    }
}
