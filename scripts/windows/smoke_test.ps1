[CmdletBinding()]
param(
    [string]$ConfigPath,
    [int]$MonitorDurationSeconds = 45
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$paths = Get-WindowsPaths -ConfigPath $ConfigPath
$statePath = Join-Path $paths.StateRoot "hako_drone_service.json"
$monitorReport = Join-Path $paths.LogsRoot "phase-w1-smoke-monitor.json"
$missionReport = Join-Path $paths.LogsRoot "phase-w1-smoke-mission.json"
$resultPath = Join-Path $paths.LogsRoot "phase-w1-smoke-result.json"
$monitor = $null

try {
    if (Test-Path -LiteralPath $statePath) {
        & (Join-Path $PSScriptRoot "stop_all.ps1") -ConfigPath $ConfigPath
    }

    & (Join-Path $PSScriptRoot "ensure_hako_mmap.ps1")
    & (Join-Path $PSScriptRoot "prepare_scenario.ps1") -ConfigPath $ConfigPath -Refresh
    & (Join-Path $PSScriptRoot "start_simulation.ps1") -ConfigPath $ConfigPath

    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    Set-HakoChildEnvironment -Paths $paths
    $pduConfig = Join-Path $paths.ScenarioRoot "config\pdudef\webavatar.json"

    $monitorArgs = @(
        (Join-Path $PSScriptRoot "monitor_phase_w1.py"),
        "--config", $pduConfig,
        "--duration", $MonitorDurationSeconds,
        "--interval", "0.001",
        "--report", $monitorReport
    )
    $monitorParams = @{
        FilePath = $paths.Python
        ArgumentList = $monitorArgs
        WorkingDirectory = $paths.RepositoryRoot
        RedirectStandardOutput = Join-Path $paths.LogsRoot "phase-w1-smoke-monitor.stdout.log"
        RedirectStandardError = Join-Path $paths.LogsRoot "phase-w1-smoke-monitor.stderr.log"
        WindowStyle = "Hidden"
        PassThru = $true
    }
    $monitor = Start-Process @monitorParams

    Start-Sleep -Seconds 1
    $missionScript = Join-Path $PSScriptRoot "run_collision_mission.py"
    & $paths.Python $missionScript --config $pduConfig --report $missionReport
    $missionExit = $LASTEXITCODE

    Wait-Process -Id $monitor.Id -Timeout ($MonitorDurationSeconds + 10)
    $monitor.Refresh()
    $monitorExit = $monitor.ExitCode

    $monitorData = Get-Content -LiteralPath $monitorReport -Raw | ConvertFrom-Json
    $missionData = Get-Content -LiteralPath $missionReport -Raw | ConvertFrom-Json
    $after = $missionData.afterMove.position
    $wallStopObserved = (
        $after.x -ge -19.0 -and $after.x -le -17.0 -and
        $after.y -ge 10.0 -and $after.y -le 12.0
    )

    $checks = [ordered]@{
        serviceRunning = $state.status -eq "running"
        runtimeMujoco37 = (
            $state.mujocoVersion.StartsWith("3.7") -and
            ([System.IO.Path]::GetFullPath($state.mujocoDll)).Equals(
                [System.IO.Path]::GetFullPath((Join-Path $paths.SimBin "mujoco.dll")),
                [System.StringComparison]::OrdinalIgnoreCase
            )
        )
        positionPduReadable = $monitorData.sampleCount -gt 0
        takeoffSucceeded = [bool]$missionData.takeoffSucceeded
        buildingWallStopObserved = $wallStopObserved
        droneStatusCollisionIncreased = $monitorData.collidedCountIncrease -gt 0
        monitorCompleted = $monitorExit -eq 0
        missionCompleted = $missionExit -eq 0
    }
    $passed = -not ($checks.Values -contains $false)

    $result = [ordered]@{
        generatedAt = (Get-Date).ToString("o")
        status = if ($passed) { "PASS" } else { "FAIL" }
        checks = $checks
        runtime = [ordered]@{
            pid = $state.pid
            executable = $state.executable
            mujocoDll = $state.mujocoDll
            mujocoVersion = $state.mujocoVersion
            coreConfig = $state.coreConfig
            mmapRoot = $state.mmapRoot
        }
        collision = [ordered]@{
            target = $missionData.target
            afterMove = $missionData.afterMove
            moveSucceeded = $missionData.moveSucceeded
            initialCollidedCounts = $monitorData.initialCollidedCounts
            maxCollidedCounts = $monitorData.maxCollidedCounts
            collidedCountIncrease = $monitorData.collidedCountIncrease
            maxDroneStatusEvent = $monitorData.maxDroneStatusEvent
            impulseCollisionEventCount = $monitorData.impulseCollisionEventCount
            impulsePduRole = "external impulse input; native MuJoCo contact output is DroneStatus.collided_counts"
        }
        reports = [ordered]@{
            monitor = $monitorReport
            mission = $missionReport
        }
    }
    $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding utf8
    $result | ConvertTo-Json -Depth 12
    if (-not $passed) {
        exit 1
    }
} finally {
    if ($null -ne $monitor) {
        $liveMonitor = Get-Process -Id $monitor.Id -ErrorAction SilentlyContinue
        if ($null -ne $liveMonitor) {
            Stop-Process -Id $monitor.Id -Force
        }
    }
    if (Test-Path -LiteralPath $statePath) {
        & (Join-Path $PSScriptRoot "stop_all.ps1") -ConfigPath $ConfigPath
    }
}
