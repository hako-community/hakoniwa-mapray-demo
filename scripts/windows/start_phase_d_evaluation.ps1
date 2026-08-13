[CmdletBinding()]
param(
    [ValidateRange(1, 99)]
    [int]$ParticipantNumber,
    [ValidateSet(1, 2)]
    [int]$Sequence,
    [ValidateRange(1, 65535)]
    [int]$HttpPort = 18080,
    [ValidateSet("auto", "edge", "chrome")]
    [string]$Browser = "chrome",
    [switch]$NoLaunch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

function Find-EvaluationBrowser {
    param([Parameter(Mandatory)][string]$Requested)
    $edge = @(
        (Join-Path ${env:ProgramFiles(x86)} "Microsoft\Edge\Application\msedge.exe"),
        (Join-Path $env:ProgramFiles "Microsoft\Edge\Application\msedge.exe")
    )
    $chrome = @(
        (Join-Path $env:ProgramFiles "Google\Chrome\Application\chrome.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Google\Chrome\Application\chrome.exe"),
        (Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe")
    )
    $candidates = switch ($Requested) {
        "edge" { $edge }
        "chrome" { $chrome }
        default { @($edge) + @($chrome) }
    }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }
    throw "Chrome or Edge was not found for Browser='$Requested'."
}

$participantId = "P{0:D2}" -f $ParticipantNumber
$oddParticipant = $ParticipantNumber % 2 -eq 1
if ($Sequence -eq 1) {
    $trialId = "D-SEED-A"
    $seed = 20260821
    $evaluationMode = if ($oddParticipant) { "mapray" } else { "leaflet" }
} else {
    $trialId = "D-SEED-B"
    $seed = 20260822
    $evaluationMode = if ($oddParticipant) { "leaflet" } else { "mapray" }
}

$query = [ordered]@{
    scenarioConfig = "/hakoniwa-geo-viewer/config/viewer-config-shibuya.json"
    threejsRoot = "/hakoniwa-web3d-drone"
    scenarioMode = "fixture"
    fleetSize = 30
    seed = $seed
    phaseDEvaluation = 1
    evaluationMode = $evaluationMode
    participantId = $participantId
    trialId = $trialId
}
$queryString = ($query.GetEnumerator() | ForEach-Object {
    "{0}={1}" -f `
        [Uri]::EscapeDataString([string]$_.Key),
        [Uri]::EscapeDataString([string]$_.Value)
}) -join "&"
$viewerUri = "http://localhost:$HttpPort/hakoniwa-geo-viewer/src/client/index.html?$queryString"

try {
    $probe = Invoke-WebRequest -UseBasicParsing -Uri $viewerUri -TimeoutSec 5
    if ($probe.StatusCode -ne 200) { throw "HTTP $($probe.StatusCode)" }
} catch {
    throw "Viewer is not reachable at http://localhost:$HttpPort. Start serve_geo_viewer.py first. $($_.Exception.Message)"
}

$paths = Get-WindowsPaths
$logsRoot = $paths.LogsRoot
Assert-PathIsWorkspaceOwned -Path $logsRoot -RepositoryRoot $paths.RepositoryRoot
New-Item -ItemType Directory -Force -Path $logsRoot | Out-Null
$manifestPath = Join-Path $logsRoot "phase-d-$participantId-sequence$Sequence-launch.json"
$manifest = [ordered]@{
    schemaVersion = 1
    evaluationId = "phase-d-mapray-leaflet-operations-20260812"
    participantId = $participantId
    sequence = $Sequence
    trialId = $trialId
    mode = $evaluationMode
    seed = $seed
    viewerUri = $viewerUri
    status = if ($NoLaunch) { "prepared" } else { "launched" }
    launchedAt = (Get-Date).ToString("o")
}
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding utf8

if (-not $NoLaunch) {
    $browserPath = Find-EvaluationBrowser -Requested $Browser
    Start-Process -FilePath $browserPath -ArgumentList @("--new-window", $viewerUri) | Out-Null
}

$manifest | ConvertTo-Json -Depth 4
Write-Host "Launch manifest: $manifestPath" -ForegroundColor Green
Write-Host "After completion, save both CSV and JSON from the Phase D panel." -ForegroundColor Cyan
