[CmdletBinding()]
param(
    [ValidateSet("fixture", "core")]
    [string]$Mode = "fixture",
    [int]$FleetSize = 10,
    [int]$HttpPort = 18080,
    [int]$WebSocketPort = 8765,
    [switch]$NoBrowser
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$paths = Get-WindowsPaths
$viewerUrl = ""

if ($Mode -eq "core") {
    Write-Host "[5km Demo] Starting in Hakoniwa Core / PDU mode (Tokyo Tower 5km, Fleet: $FleetSize)..." -ForegroundColor Cyan
    $coreLauncher = Join-Path $PSScriptRoot "start_core_fleet_demo.ps1"
    & $coreLauncher -ScenarioName "tokyo-tower" -FleetSize $FleetSize -HttpPort $HttpPort -WebSocketPort $WebSocketPort
    return
}

# Mode == "fixture"
Write-Host "[5km Demo] Starting in Fixture mode (Tokyo Tower 5km Comparison, Fleet: $FleetSize)..." -ForegroundColor Cyan

$httpScript = Join-Path $PSScriptRoot "serve_geo_viewer.py"
$envFile = Join-Path $paths.RepositoryRoot "runtime\windows\config\.env"
$stateFile = Join-Path $paths.StateRoot "demo-5km-http.json"

# Check if HTTP server is already running on $HttpPort
$client = [System.Net.Sockets.TcpClient]::new()
$portInUse = $false
try {
    $connect = $client.ConnectAsync("127.0.0.1", $HttpPort)
    if ($connect.Wait(300)) {
        $portInUse = $client.Connected
    }
} catch {
    $portInUse = $false
} finally {
    $client.Dispose()
}

if (-not $portInUse) {
    Write-Host "[5km Demo] Launching Geo Viewer HTTP server on port $HttpPort..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $paths.LogsRoot, $paths.StateRoot | Out-Null
    $httpLog = Join-Path $paths.LogsRoot "demo-5km-http.log"
    $httpErr = Join-Path $paths.LogsRoot "demo-5km-http.err"

    $httpArgs = @(
        $httpScript,
        "--directory", $paths.RepositoryRoot,
        "--port", $HttpPort,
        "--bind", "0.0.0.0"
    )
    if (Test-Path -LiteralPath $envFile) {
        $httpArgs += @("--env-file", $envFile)
    }

    $proc = Start-Process -FilePath $paths.Python -ArgumentList $httpArgs -WorkingDirectory $paths.RepositoryRoot -RedirectStandardOutput $httpLog -RedirectStandardError $httpErr -WindowStyle "Hidden" -PassThru
    Start-Sleep -Seconds 1
    if ($proc.HasExited) {
        throw "Failed to start HTTP server. See $httpErr"
    }
    @{ pid = $proc.Id; port = $HttpPort } | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding utf8
} else {
    Write-Host "[5km Demo] HTTP server is already active on port $HttpPort." -ForegroundColor Green
}

$viewerUrl = "http://localhost:$HttpPort/hakoniwa-geo-viewer/src/client/index.html?scenarioConfig=/hakoniwa-geo-viewer/config/viewer-config-tokyo-tower-5km.json&threejsRoot=/hakoniwa-web3d-drone&scenarioMode=fixture&fleetSize=$FleetSize"

Write-Host ""
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host " [5km Comparison Demo Ready]" -ForegroundColor Green
Write-Host " URL: $viewerUrl" -ForegroundColor White
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""

if (-not $NoBrowser) {
    Start-Process $viewerUrl
}
