[CmdletBinding()]
param(
    [ValidatePattern("^[A-Za-z0-9_-]+$")]
    [string]$ScenarioName = "shibuya",
    [string]$GeneratedDirectory,
    [string]$DestinationDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

function Get-LowerSha256 {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-ExpectedHash {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Expected,
        [Parameter(Mandatory)][string]$Label
    )
    $actual = Get-LowerSha256 -Path $Path
    if ($actual -ne $Expected.ToLowerInvariant()) {
        throw "$Label hash mismatch: expected=$Expected actual=$actual path=$Path"
    }
}

$repositoryRoot = Get-RepositoryRoot
$geoViewerRoot = Join-Path $repositoryRoot "hakoniwa-geo-viewer"
if ([string]::IsNullOrWhiteSpace($GeneratedDirectory)) {
    $GeneratedDirectory = Join-Path $repositoryRoot "runtime\windows\generated\$ScenarioName"
}
if ([string]::IsNullOrWhiteSpace($DestinationDirectory)) {
    $DestinationDirectory = Join-Path $geoViewerRoot "runtime-assets\$ScenarioName"
}

$generatedRoot = [System.IO.Path]::GetFullPath($GeneratedDirectory)
$destinationRoot = [System.IO.Path]::GetFullPath($DestinationDirectory)
Assert-PathIsWorkspaceOwned -Path $generatedRoot -RepositoryRoot $repositoryRoot
Assert-PathIsWorkspaceOwned -Path $destinationRoot -RepositoryRoot $repositoryRoot
$runtimeAssetsRoot = [System.IO.Path]::GetFullPath((Join-Path $geoViewerRoot "runtime-assets")).TrimEnd("\")
if (-not $destinationRoot.StartsWith($runtimeAssetsRoot + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Viewer assets must be deployed below $runtimeAssetsRoot"
}

$terrainGridSource = Join-Path $generatedRoot "terrain-grid.json"
$buildingsSource = Join-Path $generatedRoot "buildings.xml"
$buildingsLod1Source = Join-Path $generatedRoot "buildings-lod1.json"
$cityManifestSource = Join-Path $generatedRoot "manifest.json"
$terrainManifestSource = Join-Path $generatedRoot "terrain-manifest.json"
foreach ($path in @($terrainGridSource, $buildingsSource, $buildingsLod1Source, $cityManifestSource, $terrainManifestSource)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "R1 deployment prerequisite missing: $path"
    }
}

$cityManifest = Get-Content -LiteralPath $cityManifestSource -Raw | ConvertFrom-Json
$terrainManifest = Get-Content -LiteralPath $terrainManifestSource -Raw | ConvertFrom-Json
Assert-ExpectedHash `
    -Path $buildingsSource `
    -Expected $cityManifest.files.'buildings.xml'.sha256 `
    -Label "buildings.xml source manifest"
Assert-ExpectedHash `
    -Path $buildingsLod1Source `
    -Expected $cityManifest.files.'buildings-lod1.json'.sha256 `
    -Label "buildings-lod1.json source manifest"
Assert-ExpectedHash `
    -Path $terrainGridSource `
    -Expected $terrainManifest.files.'terrain-grid.json'.sha256 `
    -Label "terrain-grid.json source manifest"

$grid = Get-Content -LiteralPath $terrainGridSource -Raw | ConvertFrom-Json
if ($grid.schemaVersion -ne 1) {
    throw "Unsupported terrain-grid schemaVersion: $($grid.schemaVersion)"
}
if ($grid.frame -ne "mujoco_x_north_y_minus_east_z_up") {
    throw "Unsupported terrain-grid frame: $($grid.frame)"
}
$rows = [int]$grid.rows
$columns = [int]$grid.columns
if ($rows -lt 2 -or $columns -lt 2 -or $grid.modelHeightsM.Count -ne $rows * $columns) {
    throw "Invalid terrain-grid dimensions or modelHeightsM length"
}
foreach ($value in $grid.modelHeightsM) {
    $number = [double]$value
    if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) {
        throw "terrain-grid contains a non-finite model height"
    }
}
foreach ($value in @($grid.xMinM, $grid.xMaxM, $grid.yMinM, $grid.yMaxM, $grid.zBaselineM)) {
    $number = [double]$value
    if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) {
        throw "terrain-grid coordinate metadata contains a non-finite value"
    }
}
if ([double]$grid.xMinM -ge [double]$grid.xMaxM -or [double]$grid.yMinM -ge [double]$grid.yMaxM) {
    throw "terrain-grid bounds must be increasing"
}

New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
$copyPlan = @(
    [pscustomobject]@{ Source = $terrainGridSource; Name = "terrain-grid.json" },
    [pscustomobject]@{ Source = $buildingsSource; Name = "buildings.xml" },
    [pscustomobject]@{ Source = $buildingsLod1Source; Name = "buildings-lod1.json" },
    [pscustomobject]@{ Source = $cityManifestSource; Name = "city-pipeline-manifest.json" },
    [pscustomobject]@{ Source = $terrainManifestSource; Name = "terrain-source-manifest.json" }
)

$deployedFiles = foreach ($item in $copyPlan) {
    $destination = Join-Path $destinationRoot $item.Name
    Copy-Item -LiteralPath $item.Source -Destination $destination -Force
    $sourceHash = Get-LowerSha256 -Path $item.Source
    $destinationHash = Get-LowerSha256 -Path $destination
    if ($sourceHash -ne $destinationHash) {
        throw "Deployed file hash mismatch: $($item.Name)"
    }
    [ordered]@{
        path = $item.Name
        bytes = (Get-Item -LiteralPath $destination).Length
        sha256 = $destinationHash
        sourceRelativePath = [System.IO.Path]::GetRelativePath($repositoryRoot, $item.Source).Replace("\", "/")
    }
}

$deploymentManifest = [ordered]@{
    schemaVersion = 1
    scenarioId = $ScenarioName
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    coordinateContract = [ordered]@{
        frame = $grid.frame
        rows = $rows
        columns = $columns
        xMinM = [double]$grid.xMinM
        xMaxM = [double]$grid.xMaxM
        yMinM = [double]$grid.yMinM
        yMaxM = [double]$grid.yMaxM
        zBaselineM = [double]$grid.zBaselineM
        threeModelHeight = "modelHeightsM"
        mujocoModelHeight = "modelHeightsM"
        maprayAbsoluteHeight = "modelHeightsM + zBaselineM"
    }
    files = @($deployedFiles)
}
$deploymentManifestPath = Join-Path $destinationRoot "manifest.json"
$deploymentManifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $deploymentManifestPath -Encoding utf8

$verifiedManifest = Get-Content -LiteralPath $deploymentManifestPath -Raw | ConvertFrom-Json
if ($verifiedManifest.files.Count -ne $copyPlan.Count) {
    throw "Deployment manifest verification failed"
}

Write-Host "Phase R1 viewer assets deployed."
Write-Host "  Source      : $generatedRoot"
Write-Host "  Destination : $destinationRoot"
Write-Host "  Manifest    : $deploymentManifestPath"
$deploymentManifest | ConvertTo-Json -Depth 10
