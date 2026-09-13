[CmdletBinding()]
param(
    [string]$AirframeDatasetId = "",
    [string]$PropellerDatasetId = "",
    [ValidateSet("model", "pin", "both")]
    [string]$RenderMode = "model",
    [ValidateSet(1, 5, 10)]
    [int]$FleetSize = 1,
    [int]$HttpPort = 18080,
    [int]$ReadyTimeoutSeconds = 10,
    [switch]$NoBrowser
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

function Test-MaprayModelHttpServer {
    param([Parameter(Mandatory)][string]$ProbeUri)
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $ProbeUri -TimeoutSec 5
        return $response.StatusCode -eq 200 -and $response.Content -match "Mapray 0.9.6 Drone Model Demo"
    } catch {
        return $false
    }
}

foreach ($value in @($AirframeDatasetId, $PropellerDatasetId)) {
    if (-not [string]::IsNullOrWhiteSpace($value) -and $value -notmatch '^\d+$') {
        throw "Mapray 3D Dataset IDs must contain digits only."
    }
}

$paths = Get-WindowsPaths
$httpScript = Join-Path $PSScriptRoot "serve_geo_viewer.py"
$envFile = $paths.MaprayEnvFile
$stateFile = Join-Path $paths.StateRoot "mapray-drone-model-http.json"
$webAssetRoot = $paths.WorkspaceRoot
$viewerPath = "/hakoniwa-geo-viewer/src/client/mapray-drone-model.html"
$viewerProbeUri = "http://localhost:$HttpPort$viewerPath"

foreach ($item in @(
    (Join-Path $paths.GeoViewerRoot "src\client\mapray-drone-model.html"),
    (Join-Path $paths.GeoViewerRoot "src\client\src\mapray_drone_model_demo.js"),
    (Join-Path $paths.GeoViewerRoot "src\client\src\mapray_drone_model_layer.mjs"),
    (Join-Path $paths.GeoViewerRoot "src\client\src\mapray_drone_pose.mjs"),
    (Join-Path $paths.GeoViewerRoot "src\client\src\mapray_model_phase0.mjs"),
    (Join-Path $paths.GeoViewerRoot "config\mapray-drone-model.json"),
    $envFile
)) {
    if (-not (Test-Path -LiteralPath $item -PathType Leaf)) {
        throw "Mapray drone model prerequisite missing: $item"
    }
}

$portInUse = Test-LocalTcpPort -Port $HttpPort
if (-not $portInUse) {
    New-Item -ItemType Directory -Force -Path $paths.LogsRoot, $paths.StateRoot | Out-Null
    $httpLog = Join-Path $paths.LogsRoot "mapray-drone-model-http.log"
    $httpErr = Join-Path $paths.LogsRoot "mapray-drone-model-http.err"
    $httpArgs = @(
        $httpScript,
        "--directory", $webAssetRoot,
        "--port", $HttpPort,
        "--bind", "0.0.0.0",
        "--env-file", $envFile
    )
    $proc = Start-Process -FilePath $paths.Python -ArgumentList $httpArgs `
        -WorkingDirectory $webAssetRoot -RedirectStandardOutput $httpLog `
        -RedirectStandardError $httpErr -WindowStyle Hidden -PassThru
    $deadline = (Get-Date).AddSeconds($ReadyTimeoutSeconds)
    do {
        Start-Sleep -Milliseconds 200
        $proc.Refresh()
        if ($proc.HasExited) { throw "Mapray drone model HTTP server exited. See $httpErr" }
        $serverReady = Test-MaprayModelHttpServer -ProbeUri $viewerProbeUri
    } while ((Get-Date) -lt $deadline -and -not $serverReady)
    if (-not $serverReady) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        throw "Mapray drone model HTTP server was not ready before timeout. See $httpErr"
    }
    @{
        pid = $proc.Id
        processName = $proc.ProcessName
        processStartTimeUtc = $proc.StartTime.ToUniversalTime().ToString("o")
        port = $HttpPort
        webAssetRoot = $webAssetRoot
        viewerProbeUri = $viewerProbeUri
        purpose = "mapray-drone-model"
    } | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding utf8
} elseif (-not (Test-MaprayModelHttpServer -ProbeUri $viewerProbeUri)) {
    throw "Port $HttpPort is occupied by an incompatible HTTP server."
}

$query = [System.Collections.Generic.List[string]]::new()
$query.Add("droneRender=$RenderMode")
$query.Add("fleetSize=$FleetSize")
if (-not [string]::IsNullOrWhiteSpace($AirframeDatasetId)) {
    $query.Add("airframeDatasetId=$AirframeDatasetId")
}
if (-not [string]::IsNullOrWhiteSpace($PropellerDatasetId)) {
    $query.Add("propellerDatasetId=$PropellerDatasetId")
}
$viewerUrl = "http://localhost:$HttpPort$viewerPath"
if ($query.Count -gt 0) { $viewerUrl += "?" + ($query -join "&") }

Write-Host "Mapray 0.9.6 Drone Model Demo" -ForegroundColor Cyan
Write-Host "URL: $viewerUrl"
if (-not $NoBrowser) { Start-Process $viewerUrl }
