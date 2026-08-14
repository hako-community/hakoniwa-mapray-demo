[CmdletBinding()]
param(
    [ValidateSet("shibuya", "tokyo-tower")]
    [string]$ScenarioName = "shibuya",
    [ValidateSet(10, 20, 30)]
    [int]$FleetSize = 30,
    [int]$Seed = 20260811,
    [int]$WebSocketPort = 8765,
    [int]$HttpPort = 18080,
    [int]$ReadyTimeoutSeconds = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

function Test-LocalTcpPort {
    param([int]$Port)
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $connect = $client.ConnectAsync("127.0.0.1", $Port)
        if (-not $connect.Wait(300)) { return $false }
        return $client.Connected
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

$paths = Get-WindowsPaths
$statePath = Join-Path $paths.StateRoot "core-fleet-demo.json"
$simulationStatePath = Join-Path $paths.StateRoot "hako_drone_service.json"
$readyFile = Join-Path $paths.StateRoot "core-fleet-viewer.ready"
$conductorScript = Join-Path $PSScriptRoot "core_fleet_conductor.py"
$publisherScript = Join-Path $PSScriptRoot "core_fleet_state_publisher.py"
$bridgeScript = Join-Path $PSScriptRoot "pdu_web_bridge.py"
$httpScript = Join-Path $PSScriptRoot "serve_geo_viewer.py"
$pduConfig = Join-Path $paths.RepositoryRoot "runtime\windows\core-fleet\config\pdudef\drone-visual-state.json"
$viewerConfigRoot = Join-Path $paths.RepositoryRoot "hakoniwa-geo-viewer\config"
$scenarioPath = Join-Path $viewerConfigRoot "scenarios\$ScenarioName.json"
$viewerConfigPath = Join-Path $viewerConfigRoot "viewer-config-$ScenarioName.json"
$scenario = if (Test-Path -LiteralPath $scenarioPath) {
    Get-Content -LiteralPath $scenarioPath -Raw | ConvertFrom-Json
} else {
    $null
}
$scenarioDirectory = Split-Path -Parent $scenarioPath
$operations = if ($null -ne $scenario) {
    [System.IO.Path]::GetFullPath((Join-Path $scenarioDirectory ([string]$scenario.paths.operationsLayer)))
} else {
    ""
}
$geoOriginPath = if ($null -ne $scenario) {
    [System.IO.Path]::GetFullPath((Join-Path $scenarioDirectory ([string]$scenario.paths.geoOrigin)))
} else {
    ""
}
$geoOrigin = if (Test-Path -LiteralPath $geoOriginPath) {
    Get-Content -LiteralPath $geoOriginPath -Raw | ConvertFrom-Json
} else {
    $null
}
$hakoCmd = Join-Path $paths.CoreBin "hako-cmd.exe"
$conductorLog = Join-Path $paths.LogsRoot "core-fleet-conductor.log"
$conductorErr = Join-Path $paths.LogsRoot "core-fleet-conductor.err"
$publisherLog = Join-Path $paths.LogsRoot "core-fleet-publisher.log"
$publisherErr = Join-Path $paths.LogsRoot "core-fleet-publisher.err"
$bridgeLog = Join-Path $paths.LogsRoot "core-fleet-bridge.log"
$bridgeErr = Join-Path $paths.LogsRoot "core-fleet-bridge.err"
$httpLog = Join-Path $paths.LogsRoot "core-fleet-http.log"
$httpErr = Join-Path $paths.LogsRoot "core-fleet-http.err"

foreach ($item in @(
    $paths.Python,
    $hakoCmd,
    $conductorScript,
    $publisherScript,
    $bridgeScript,
    $httpScript,
    $pduConfig,
    $scenarioPath,
    $viewerConfigPath,
    $operations,
    $geoOriginPath
)) {
    if (-not (Test-Path -LiteralPath $item)) {
        throw "Core fleet prerequisite missing: $item"
    }
}
if ($null -eq $geoOrigin -or $null -eq $geoOrigin.origin) {
    throw "Scenario origin is invalid: $geoOriginPath"
}
$originLatitude = ([double]$geoOrigin.origin.latitude).ToString(
    [System.Globalization.CultureInfo]::InvariantCulture
)
$originLongitude = ([double]$geoOrigin.origin.longitude).ToString(
    [System.Globalization.CultureInfo]::InvariantCulture
)
if (Test-Path -LiteralPath $statePath) {
    throw "Core fleet demo state already exists. Run stop_core_fleet_demo.ps1 first."
}
if (Test-Path -LiteralPath $simulationStatePath) {
    throw "Another workspace Hakoniwa simulation is recorded at $simulationStatePath. Stop it before starting the core fleet demo."
}
if (Test-LocalTcpPort -Port $WebSocketPort) {
    throw "WebSocket port $WebSocketPort is already in use."
}

Assert-PathIsWorkspaceOwned -Path $paths.MmapRoot -RepositoryRoot $paths.RepositoryRoot
Assert-PathIsWorkspaceOwned -Path $paths.StateRoot -RepositoryRoot $paths.RepositoryRoot
New-Item -ItemType Directory -Force -Path $paths.MmapRoot, $paths.LogsRoot, $paths.StateRoot | Out-Null
Set-HakoChildEnvironment -Paths $paths

Get-ChildItem -LiteralPath $paths.MmapRoot -Force -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force
$mmapFile = Join-Path $paths.MmapRoot "mmap-0x100.bin"
$stream = [System.IO.File]::Open(
    $mmapFile,
    [System.IO.FileMode]::Create,
    [System.IO.FileAccess]::Write,
    [System.IO.FileShare]::ReadWrite
)
try {
    $stream.SetLength(5MB)
} finally {
    $stream.Dispose()
}
if (Test-Path -LiteralPath $readyFile) {
    Remove-Item -LiteralPath $readyFile -Force
}

$conductor = $null
$publisher = $null
$bridge = $null
$http = $null
$httpManaged = $false
try {
    $conductor = Start-Process -FilePath $paths.Python -ArgumentList @(
        $conductorScript,
        "--delta-time-usec", "20000",
        "--max-delay-usec", "200000"
    ) -WorkingDirectory $paths.RepositoryRoot -RedirectStandardOutput $conductorLog `
        -RedirectStandardError $conductorErr -WindowStyle Hidden -PassThru

    $deadline = (Get-Date).AddSeconds($ReadyTimeoutSeconds)
    $masterReady = $false
    do {
        Start-Sleep -Milliseconds 200
        $conductor.Refresh()
        if ($conductor.HasExited) {
            throw "Hakoniwa conductor exited with code $($conductor.ExitCode). See $conductorErr"
        }
        & $hakoCmd ls 2>&1 | Out-Null
        $masterReady = $LASTEXITCODE -eq 0
    } while ((Get-Date) -lt $deadline -and -not $masterReady)
    if (-not $masterReady) {
        throw "Hakoniwa master/conductor was not ready before timeout. See $conductorErr"
    }

    $publisher = Start-Process -FilePath $paths.Python -ArgumentList @(
        $publisherScript,
        "--pdu-config", $pduConfig,
        "--operations", $operations,
        "--fleet-size", $FleetSize,
        "--seed", $Seed,
        "--origin-latitude", $originLatitude,
        "--origin-longitude", $originLongitude,
        "--ready-file", $readyFile
    ) -WorkingDirectory $paths.RepositoryRoot -RedirectStandardOutput $publisherLog `
        -RedirectStandardError $publisherErr -WindowStyle Hidden -PassThru

    $deadline = (Get-Date).AddSeconds($ReadyTimeoutSeconds)
    $registered = $false
    $lastLs = ""
    do {
        Start-Sleep -Milliseconds 200
        $publisher.Refresh()
        if ($publisher.HasExited) {
            throw "Core fleet publisher exited with code $($publisher.ExitCode). See $publisherErr"
        }
        $lastLs = (& $hakoCmd ls 2>&1 | Out-String).Trim()
        $registered = $LASTEXITCODE -eq 0 -and $lastLs -match "DroneVisualStatePublisher"
    } while ((Get-Date) -lt $deadline -and -not $registered)
    if (-not $registered) {
        throw "Core fleet publisher was not registered. Last hako-cmd ls: $lastLs"
    }

    $bridge = Start-Process -FilePath $paths.Python -ArgumentList @(
        $bridgeScript,
        "--profile", "fleets",
        "--host", "127.0.0.1",
        "--port", $WebSocketPort,
        "--interval", "0.02",
        "--ready-file", $readyFile
    ) -WorkingDirectory $paths.RepositoryRoot -RedirectStandardOutput $bridgeLog `
        -RedirectStandardError $bridgeErr -WindowStyle Hidden -PassThru

    if (Test-LocalTcpPort -Port $HttpPort) {
        $probeUri = "http://localhost:$HttpPort/hakoniwa-geo-viewer/src/client/index.html"
        $probe = Invoke-WebRequest -UseBasicParsing -Uri $probeUri -TimeoutSec 5
        if ($probe.StatusCode -ne 200 -or $probe.Content -notmatch "Hakoniwa Geo") {
            throw "Port $HttpPort is occupied by an incompatible HTTP server."
        }
    } else {
        $http = Start-Process -FilePath $paths.Python -ArgumentList @(
            $httpScript,
            "--directory", $paths.RepositoryRoot,
            "--port", $HttpPort,
            "--bind", "127.0.0.1",
            "--env-file", (Join-Path $paths.RepositoryRoot "runtime\windows\config\.env")
        ) -WorkingDirectory $paths.RepositoryRoot -RedirectStandardOutput $httpLog `
            -RedirectStandardError $httpErr -WindowStyle Hidden -PassThru
        $httpManaged = $true
    }

    $deadline = (Get-Date).AddSeconds($ReadyTimeoutSeconds)
    do {
        Start-Sleep -Milliseconds 200
        $bridge.Refresh()
        if ($bridge.HasExited) {
            throw "Core fleet bridge exited with code $($bridge.ExitCode). See $bridgeErr"
        }
        if ($httpManaged) {
            $http.Refresh()
            if ($http.HasExited) {
                throw "Core fleet HTTP server exited with code $($http.ExitCode). See $httpErr"
            }
        }
        $wsReady = Test-LocalTcpPort -Port $WebSocketPort
        $httpReady = Test-LocalTcpPort -Port $HttpPort
    } while ((Get-Date) -lt $deadline -and (-not $wsReady -or -not $httpReady))
    if (-not $wsReady -or -not $httpReady) {
        throw "Core fleet listeners were not ready (WebSocket=$wsReady HTTP=$httpReady)."
    }

    $startOutput = (& $hakoCmd start 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "hako-cmd start failed: $startOutput"
    }
    $viewerUrl = "http://localhost:$HttpPort/hakoniwa-geo-viewer/src/client/index.html?" +
        "scenarioConfig=/hakoniwa-geo-viewer/config/viewer-config-$ScenarioName.json&" +
        "threejsRoot=/hakoniwa-web3d-drone&scenarioMode=live&liveProfile=kinematic&" +
        "fleetSize=$FleetSize&seed=$Seed&maprayBuildings=public-wide&autoConnect=1"
    $state = [ordered]@{
        status = "running"
        source = "hakoniwa-core-kinematic"
        scenarioName = $ScenarioName
        scenarioPath = $scenarioPath
        operations = $operations
        origin = [ordered]@{
            latitude = [double]$geoOrigin.origin.latitude
            longitude = [double]$geoOrigin.origin.longitude
        }
        startedAt = (Get-Date).ToString("o")
        fleetSize = $FleetSize
        seed = $Seed
        conductorPid = $conductor.Id
        publisherPid = $publisher.Id
        bridgePid = $bridge.Id
        httpManaged = $httpManaged
        httpPid = if ($httpManaged) { $http.Id } else { $null }
        readyFile = $readyFile
        websocketUri = "ws://127.0.0.1:$WebSocketPort"
        viewerUrl = $viewerUrl
        conductorLog = $conductorLog
        conductorErr = $conductorErr
        publisherLog = $publisherLog
        publisherErr = $publisherErr
        bridgeLog = $bridgeLog
        bridgeErr = $bridgeErr
        httpLog = if ($httpManaged) { $httpLog } else { $null }
        httpErr = if ($httpManaged) { $httpErr } else { $null }
        hakoCmdStart = $startOutput
    }
    $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statePath -Encoding utf8
    $state | ConvertTo-Json -Depth 5
} catch {
    if ($null -ne $conductor -and -not $conductor.HasExited) {
        & $hakoCmd stop 2>&1 | Out-Null
        & $hakoCmd reset 2>&1 | Out-Null
    }
    foreach ($process in @($bridge, $publisher, $http, $conductor)) {
        if ($null -ne $process -and -not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
    }
    throw
}
