[CmdletBinding()]
param(
    [ValidateSet("fixture", "core")]
    [string]$Mode = "fixture",
    [int]$FleetSize = 10,
    [int]$HttpPort = 18080,
    [int]$WebSocketPort = 8765,
    [int]$ReadyTimeoutSeconds = 10,
    [switch]$NoBrowser
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$paths = Get-WindowsPaths
$viewerUrl = ""

function Test-LocalTcpPort {
    param([int]$Port)

    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $connect = $client.ConnectAsync("127.0.0.1", $Port)
        if (-not $connect.Wait(300)) {
            return $false
        }
        return $client.Connected
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Test-CompatibleHttpServer {
    param(
        [Parameter(Mandatory)][string]$ProbeUri
    )

    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $ProbeUri -TimeoutSec 5
        return $response.StatusCode -eq 200 -and $response.Content -match "Hakoniwa Geo"
    } catch {
        return $false
    }
}

if ($Mode -eq "core") {
    Write-Host "[5km Demo] Starting in Hakoniwa Core / PDU mode (Tokyo Tower 5km, Fleet: $FleetSize)..." -ForegroundColor Cyan
    $coreLauncher = Join-Path $PSScriptRoot "start_core_fleet_demo.ps1"
    & $coreLauncher -ScenarioName "tokyo-tower" -FleetSize $FleetSize -HttpPort $HttpPort -WebSocketPort $WebSocketPort
    return
}

# Mode == "fixture"
Write-Host "[5km Demo] Starting in Fixture mode (Tokyo Tower 5km Comparison, Fleet: $FleetSize)..." -ForegroundColor Cyan

$httpScript = Join-Path $PSScriptRoot "serve_geo_viewer.py"
$envFile = $paths.MaprayEnvFile
$stateFile = Join-Path $paths.StateRoot "demo-5km-http.json"
$webAssetRoot = $paths.WorkspaceRoot
$viewerPath = "/hakoniwa-geo-viewer/src/client/index.html"
$viewerProbeUri = "http://localhost:$HttpPort$viewerPath"

foreach ($item in @(
    (Join-Path $paths.GeoViewerRoot "src\client\index.html"),
    (Join-Path $paths.GeoViewerRoot "config\viewer-config-tokyo-tower-5km.json"),
    $paths.Web3dDroneRoot
)) {
    if (-not (Test-Path -LiteralPath $item)) {
        throw "5km demo web prerequisite missing: $item"
    }
}

# Check if HTTP server is already running on $HttpPort
$portInUse = Test-LocalTcpPort -Port $HttpPort

if (-not $portInUse) {
    Write-Host "[5km Demo] Launching Geo Viewer HTTP server on port $HttpPort..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $paths.LogsRoot, $paths.StateRoot | Out-Null
    $httpLog = Join-Path $paths.LogsRoot "demo-5km-http.log"
    $httpErr = Join-Path $paths.LogsRoot "demo-5km-http.err"

    $httpArgs = @(
        $httpScript,
        "--directory", $webAssetRoot,
        "--port", $HttpPort,
        "--bind", "0.0.0.0"
    )
    if (Test-Path -LiteralPath $envFile) {
        $httpArgs += @("--env-file", $envFile)
    }

    $proc = Start-Process -FilePath $paths.Python -ArgumentList $httpArgs -WorkingDirectory $webAssetRoot -RedirectStandardOutput $httpLog -RedirectStandardError $httpErr -WindowStyle "Hidden" -PassThru
    $deadline = (Get-Date).AddSeconds($ReadyTimeoutSeconds)
    do {
        Start-Sleep -Milliseconds 200
        $proc.Refresh()
        if ($proc.HasExited) {
            throw "Failed to start HTTP server. See $httpErr"
        }
        $serverReady = Test-CompatibleHttpServer -ProbeUri $viewerProbeUri
    } while ((Get-Date) -lt $deadline -and -not $serverReady)
    if (-not $serverReady) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        throw "HTTP server did not serve the 5km viewer before timeout. See $httpErr"
    }
    @{
        pid = $proc.Id
        port = $HttpPort
        webAssetRoot = $webAssetRoot
        viewerProbeUri = $viewerProbeUri
    } | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding utf8
} else {
    if (-not (Test-CompatibleHttpServer -ProbeUri $viewerProbeUri)) {
        throw "Port $HttpPort is occupied by an incompatible HTTP server. Stop that server and run this script again."
    }
    Write-Host "[5km Demo] HTTP server is already active on port $HttpPort." -ForegroundColor Green
}

$viewerUrl = "http://localhost:$HttpPort${viewerPath}?scenarioConfig=/hakoniwa-geo-viewer/config/viewer-config-tokyo-tower-5km.json&threejsRoot=/hakoniwa-web3d-drone&scenarioMode=fixture&fleetSize=$FleetSize"

Write-Host ""
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host " [5km Comparison Demo Ready]" -ForegroundColor Green
Write-Host " URL: $viewerUrl" -ForegroundColor White
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""

if (-not $NoBrowser) {
    Start-Process $viewerUrl
}
