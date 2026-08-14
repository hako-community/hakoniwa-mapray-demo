[CmdletBinding()]
param(
    [string]$ConfigPath,
    [int]$ReadyTimeoutSeconds = 45
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$paths = Get-WindowsPaths -ConfigPath $ConfigPath
& (Join-Path $PSScriptRoot "ensure_hako_mmap.ps1") | Out-Null
$serviceExe = Join-Path $paths.SimBin "hako_drone_service.exe"
$hakoCmd = Join-Path $paths.CoreBin "hako-cmd.exe"
$mujocoDll = Join-Path $paths.SimBin "mujoco.dll"
$droneDirectory = "config\drone\mujoco-shibuya-api-1"
$pduConfig = "config\pdudef\webavatar.json"
$statePath = Join-Path $paths.StateRoot "hako_drone_service.json"
$stdoutPath = Join-Path $paths.LogsRoot "hako_drone_service.stdout.log"
$stderrPath = Join-Path $paths.LogsRoot "hako_drone_service.stderr.log"

foreach ($item in @(
    $serviceExe,
    $hakoCmd,
    $mujocoDll,
    $paths.CoreConfig,
    (Join-Path $paths.ScenarioRoot "$droneDirectory\drone_config_0.json"),
    (Join-Path $paths.ScenarioRoot $pduConfig)
)) {
    if (-not (Test-Path -LiteralPath $item)) {
        throw "Phase W1 is not prepared. Missing: $item. Run prepare_scenario.ps1 first."
    }
}

$mujocoVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($mujocoDll).ProductVersion
if (-not $mujocoVersion.StartsWith("3.7")) {
    throw "Refusing to start with MuJoCo '$mujocoVersion'. Expected hakoSim runtime 3.7.x: $mujocoDll"
}

if (Test-Path -LiteralPath $statePath) {
    $oldState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $oldProcess = Get-Process -Id $oldState.pid -ErrorAction SilentlyContinue
    if ($null -ne $oldProcess) {
        throw "A Phase W1 drone service is already running with PID $($oldState.pid)."
    }
    Remove-Item -LiteralPath $statePath -Force
}

Assert-PathIsWorkspaceOwned -Path $paths.MmapRoot -RepositoryRoot $paths.RepositoryRoot
New-Item -ItemType Directory -Force -Path $paths.MmapRoot, $paths.LogsRoot, $paths.StateRoot | Out-Null
$cleanupComplete = $false
for ($cleanupAttempt = 1; $cleanupAttempt -le 20; $cleanupAttempt++) {
    try {
        Get-ChildItem -LiteralPath $paths.MmapRoot -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction Stop
        $cleanupComplete = $true
        break
    } catch {
        if ($cleanupAttempt -eq 20) {
            throw
        }
        Start-Sleep -Milliseconds 250
    }
}
if (-not $cleanupComplete) {
    throw "Failed to clean workspace mmap: $($paths.MmapRoot)"
}
$mmapFile = Join-Path $paths.MmapRoot "mmap-0x100.bin"
$stream = [System.IO.File]::Open($mmapFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
try {
    $stream.SetLength(5MB)
} finally {
    $stream.Dispose()
}

Set-HakoChildEnvironment -Paths $paths
$process = $null
try {
    $startParams = @{
        FilePath = $serviceExe
        ArgumentList = @($droneDirectory, $pduConfig)
        WorkingDirectory = $paths.ScenarioRoot
        RedirectStandardOutput = $stdoutPath
        RedirectStandardError = $stderrPath
        WindowStyle = "Hidden"
        PassThru = $true
    }
    $process = Start-Process @startParams

    [ordered]@{
        pid = $process.Id
        executable = $serviceExe
        startedAt = (Get-Date).ToString("o")
        status = "starting"
        scenarioRoot = $paths.ScenarioRoot
        coreConfig = $paths.CoreConfig
        stdout = $stdoutPath
        stderr = $stderrPath
    } | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding utf8

    $deadline = (Get-Date).AddSeconds($ReadyTimeoutSeconds)
    $registered = $false
    $loadedMujoco = $null
    $lastLs = ""
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 200
        $process.Refresh()
        if ($process.HasExited) {
            throw "hako_drone_service exited with code $($process.ExitCode). See $stderrPath"
        }

        $lastLs = (& $hakoCmd ls 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and $lastLs -match "(?i)Drone") {
            $registered = $true
        }

        try {
            $live = Get-Process -Id $process.Id -ErrorAction Stop
            $loadedMujoco = $live.Modules |
                Where-Object { $_.ModuleName -ieq "mujoco.dll" } |
                Select-Object -First 1
        } catch {
            $loadedMujoco = $null
        }

        if ($registered -and $null -ne $loadedMujoco) {
            break
        }
    }
    if (-not $registered) {
        throw "Drone asset was not registered before timeout. Last 'hako-cmd ls': $lastLs"
    }
    if ($null -eq $loadedMujoco) {
        throw "The live process did not load mujoco.dll before timeout."
    }

    $actualDll = [System.IO.Path]::GetFullPath($loadedMujoco.FileName)
    $expectedDll = [System.IO.Path]::GetFullPath($mujocoDll)
    if (-not $actualDll.Equals($expectedDll, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Wrong MuJoCo DLL loaded. Expected '$expectedDll', actual '$actualDll'."
    }
    $loadedVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($actualDll).ProductVersion
    if (-not $loadedVersion.StartsWith("3.7")) {
        throw "Live process loaded MuJoCo '$loadedVersion', not 3.7.x."
    }

    $started = $false
    $startOutput = ""
    for ($attempt = 1; $attempt -le 25; $attempt++) {
        $startOutput = (& $hakoCmd start 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -eq 0) {
            $started = $true
            break
        }
        Start-Sleep -Milliseconds 200
    }
    if (-not $started) {
        throw "hako-cmd start failed after 25 attempts: $startOutput"
    }

    Start-Sleep -Seconds 2
    $process.Refresh()
    if ($process.HasExited) {
        throw "hako_drone_service exited after hako-cmd start with code $($process.ExitCode)."
    }

    $state = [ordered]@{
        pid = $process.Id
        executable = $serviceExe
        startedAt = (Get-Date).ToString("o")
        status = "running"
        scenarioRoot = $paths.ScenarioRoot
        coreConfig = $paths.CoreConfig
        mmapRoot = $paths.MmapRoot
        mujocoDll = $actualDll
        mujocoVersion = $loadedVersion
        hakoCmdList = $lastLs
        hakoCmdStart = $startOutput
        stdout = $stdoutPath
        stderr = $stderrPath
    }
    $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statePath -Encoding utf8
    $state | ConvertTo-Json -Depth 5
} catch {
    if ($null -ne $process -and -not $process.HasExited) {
        & $hakoCmd stop 2>&1 | Out-Null
        & $hakoCmd reset 2>&1 | Out-Null
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    throw
}

