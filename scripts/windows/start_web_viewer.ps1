[CmdletBinding()]
param(
    [string]$ConfigPath,
    [int]$WebSocketPort = 8765,
    [int]$HttpPort = 8001,
    [int]$ReadyTimeoutSeconds = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

function Test-LocalTcpPort {
    param([int]$Port)
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $connect = $client.ConnectAsync("127.0.0.1", $Port)
        if (-not $connect.Wait(250)) {
            return $false
        }
        return $client.Connected
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

$paths = Get-WindowsPaths -ConfigPath $ConfigPath
$w1StatePath = Join-Path $paths.StateRoot "hako_drone_service.json"
$w2StatePath = Join-Path $paths.StateRoot "phase-w2.json"
$bridgeScript = Join-Path $PSScriptRoot "pdu_web_bridge.py"
$httpServerScript = Join-Path $PSScriptRoot "serve_geo_viewer.py"
$viewerRoot = Join-Path $paths.RepositoryRoot "hakoniwa-geo-viewer"
$maprayEnvFile = Join-Path $paths.RepositoryRoot "runtime\windows\config\.env"
$bridgeLog = Join-Path $paths.LogsRoot "phase-w2-bridge.log"
$bridgeErr = Join-Path $paths.LogsRoot "phase-w2-bridge.err"
$httpLog = Join-Path $paths.LogsRoot "phase-w2-http.log"
$httpErr = Join-Path $paths.LogsRoot "phase-w2-http.err"

foreach ($item in @($w1StatePath, $bridgeScript, $httpServerScript, $viewerRoot, $paths.Python)) {
    if (-not (Test-Path -LiteralPath $item)) {
        throw "Phase W2 prerequisite missing: $item"
    }
}
$w1State = Get-Content -LiteralPath $w1StatePath -Raw | ConvertFrom-Json
$w1Process = Get-Process -Id $w1State.pid -ErrorAction SilentlyContinue
if ($null -eq $w1Process) {
    throw "Phase W1 hako_drone_service is not running. Start it before Phase W2."
}

if (Test-Path -LiteralPath $w2StatePath) {
    throw "Phase W2 state already exists. Run stop_web_viewer.ps1 first."
}
foreach ($port in @($WebSocketPort, $HttpPort)) {
    $listener = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($null -ne $listener) {
        throw "Port $port is already in use."
    }
}

Set-HakoChildEnvironment -Paths $paths
New-Item -ItemType Directory -Force -Path $paths.LogsRoot, $paths.StateRoot | Out-Null

$bridgeParams = @{
    FilePath = $paths.Python
    ArgumentList = @($bridgeScript, "--host", "127.0.0.1", "--port", $WebSocketPort, "--interval", "0.02")
    WorkingDirectory = $paths.RepositoryRoot
    RedirectStandardOutput = $bridgeLog
    RedirectStandardError = $bridgeErr
    WindowStyle = "Hidden"
    PassThru = $true
}
$httpParams = @{
    FilePath = $paths.Python
    ArgumentList = @(
        $httpServerScript,
        "--directory", $viewerRoot,
        "--port", $HttpPort,
        "--bind", "127.0.0.1",
        "--env-file", $maprayEnvFile
    )
    WorkingDirectory = $viewerRoot
    RedirectStandardOutput = $httpLog
    RedirectStandardError = $httpErr
    WindowStyle = "Hidden"
    PassThru = $true
}
$bridge = $null
$http = $null
try {
    $bridge = Start-Process @bridgeParams
    $http = Start-Process @httpParams
    $deadline = (Get-Date).AddSeconds($ReadyTimeoutSeconds)
    do {
        Start-Sleep -Milliseconds 200
        $bridge.Refresh()
        $http.Refresh()
        if ($bridge.HasExited) { throw "WebSocket bridge exited with code $($bridge.ExitCode). See $bridgeErr" }
        if ($http.HasExited) { throw "HTTP server exited with code $($http.ExitCode). See $httpErr" }
        $wsReady = Test-LocalTcpPort -Port $WebSocketPort
        $httpReady = Test-LocalTcpPort -Port $HttpPort
    } while ((Get-Date) -lt $deadline -and (-not $wsReady -or -not $httpReady))

    if (-not $wsReady -or -not $httpReady) {
        throw "Viewer listeners were not ready before timeout (WebSocket=$wsReady, HTTP=$httpReady)."
    }

    $moduleUri = "http://127.0.0.1:$HttpPort/src/client/src/terrain_height.mjs?startup-check=1"
    $moduleResponse = Invoke-WebRequest -UseBasicParsing -Uri $moduleUri -TimeoutSec 5
    $moduleContentType = [string]$moduleResponse.Headers."Content-Type"
    $moduleCacheControl = [string]$moduleResponse.Headers."Cache-Control"
    if ($moduleResponse.StatusCode -ne 200 -or $moduleContentType -notmatch "javascript") {
        throw "Viewer module HTTP contract failed: status=$($moduleResponse.StatusCode), Content-Type=$moduleContentType"
    }
    if ($moduleCacheControl -notmatch "no-store") {
        throw "Viewer module cache contract failed: Cache-Control=$moduleCacheControl"
    }

    $state = [ordered]@{
        status = "running"
        startedAt = (Get-Date).ToString("o")
        bridgePid = $bridge.Id
        httpPid = $http.Id
        websocketUri = "ws://127.0.0.1:$WebSocketPort"
        httpUri = "http://localhost:$HttpPort/src/client/index.html"
        bridgeScript = $bridgeScript
        viewerRoot = $viewerRoot
        bridgeLog = $bridgeLog
        bridgeErr = $bridgeErr
        httpLog = $httpLog
        httpErr = $httpErr
        httpServerScript = $httpServerScript
        maprayEnvFile = $maprayEnvFile
        moduleContentType = $moduleContentType
        moduleCacheControl = $moduleCacheControl
    }
    $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $w2StatePath -Encoding utf8
    $state | ConvertTo-Json -Depth 5
} catch {
    if ($null -ne $bridge -and -not $bridge.HasExited) { Stop-Process -Id $bridge.Id -Force -ErrorAction SilentlyContinue }
    if ($null -ne $http -and -not $http.HasExited) { Stop-Process -Id $http.Id -Force -ErrorAction SilentlyContinue }
    throw
}

