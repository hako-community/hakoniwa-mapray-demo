[CmdletBinding()]
param(
    [ValidateSet("mapray-full", "mapray-base", "leaflet-fallback")]
    [string]$BenchmarkMode = "mapray-full",
    [ValidateSet(10, 20, 30)]
    [int]$FleetSize = 20,
    [ValidateSet("fixture", "replay", "live")]
    [string]$ScenarioMode = "fixture",
    [ValidateRange(0, 600)]
    [int]$WarmupSeconds = 120,
    [ValidateRange(10, 3600)]
    [int]$DurationSeconds = 600,
    [int]$Seed = 20260811,
    [ValidateRange(1, 99)]
    [int]$Repeat = 1,
    [ValidateRange(1, 65535)]
    [int]$HttpPort = 18080,
    [ValidateSet("auto", "edge", "chrome")]
    [string]$Browser = "auto",
    [bool]$AutoDownload = $true,
    [switch]$NoLaunch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

function Find-BenchmarkBrowser {
    param([Parameter(Mandatory)][string]$Requested)

    $edgeCandidates = @(
        (Join-Path ${env:ProgramFiles(x86)} "Microsoft\Edge\Application\msedge.exe"),
        (Join-Path $env:ProgramFiles "Microsoft\Edge\Application\msedge.exe")
    )
    $chromeCandidates = @(
        (Join-Path $env:ProgramFiles "Google\Chrome\Application\chrome.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Google\Chrome\Application\chrome.exe"),
        (Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe")
    )
    $candidates = switch ($Requested) {
        "edge" { $edgeCandidates }
        "chrome" { $chromeCandidates }
        default { @($edgeCandidates) + @($chromeCandidates) }
    }
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }
    throw "Chrome or Edge was not found for Browser='$Requested'."
}

$paths = Get-WindowsPaths
$logsRoot = $paths.LogsRoot
Assert-PathIsWorkspaceOwned -Path $logsRoot -RepositoryRoot $paths.RepositoryRoot
New-Item -ItemType Directory -Force -Path $logsRoot | Out-Null

$runId = "{0}-{1}-{2}-seed{3}-run{4}" -f `
    $BenchmarkMode, $ScenarioMode, $FleetSize, $Seed, $Repeat
$query = [ordered]@{
    scenarioConfig = "/hakoniwa-geo-viewer/config/viewer-config-shibuya.json"
    threejsRoot = "/hakoniwa-web3d-drone"
    scenarioMode = $ScenarioMode
    fleetSize = $FleetSize
    seed = $Seed
    benchmarkMode = $BenchmarkMode
    benchmarkWarmupSec = $WarmupSeconds
    benchmarkDurationSec = $DurationSeconds
    benchmarkAutoStart = 1
    benchmarkAutoDownload = if ($AutoDownload) { 1 } else { 0 }
    benchmarkRunId = $runId
}
$queryString = ($query.GetEnumerator() | ForEach-Object {
    "{0}={1}" -f `
        [Uri]::EscapeDataString([string]$_.Key),
        [Uri]::EscapeDataString([string]$_.Value)
}) -join "&"
$viewerUri = "http://localhost:$HttpPort/hakoniwa-geo-viewer/src/client/index.html?$queryString"

try {
    $probe = Invoke-WebRequest -UseBasicParsing -Uri $viewerUri -TimeoutSec 5
    if ($probe.StatusCode -ne 200) {
        throw "HTTP $($probe.StatusCode)"
    }
} catch {
    throw "Viewer is not reachable at http://localhost:$HttpPort. Start serve_geo_viewer.py first. $($_.Exception.Message)"
}

$browserPath = if ($NoLaunch) { $null } else { Find-BenchmarkBrowser -Requested $Browser }
$manifestPath = Join-Path $logsRoot "mapray-operations-benchmark-$runId-launch.json"
$manifest = [ordered]@{
    schemaVersion = 1
    measurementKind = "actual-browser"
    estimated = $false
    status = if ($NoLaunch) { "prepared" } else { "launched" }
    runId = $runId
    launchedAt = (Get-Date).ToString("o")
    viewerUri = $viewerUri
    browserPath = $browserPath
    config = $query
    expectedMeasurementSeconds = $WarmupSeconds + $DurationSeconds
    resultLocation = if ($AutoDownload) {
        "Browser Downloads/mapray-operations-benchmark-$runId.json"
    } else {
        "Use the Browser benchmark JSON button"
    }
    note = "This launch manifest is not a benchmark result and contains no PASS/FAIL decision."
}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding utf8

if (-not $NoLaunch) {
    Start-Process -FilePath $browserPath -ArgumentList @("--new-window", $viewerUri) | Out-Null
}

$manifest | ConvertTo-Json -Depth 6
Write-Host "Launch manifest: $manifestPath" -ForegroundColor Green
Write-Host "The measurement runs for $WarmupSeconds s warmup + $DurationSeconds s actual measurement." -ForegroundColor Cyan
