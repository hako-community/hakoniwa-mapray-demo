[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string]$GeneratedDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$paths = Get-WindowsPaths -ConfigPath $ConfigPath
if (-not $GeneratedDirectory) {
    $GeneratedDirectory = Join-Path $paths.RuntimeRoot "generated\shibuya"
}
$generatedRoot = [System.IO.Path]::GetFullPath($GeneratedDirectory)
$runtimeRepositoryRoot = [System.IO.Path]::GetFullPath($paths.RepositoryRoot)
if (-not $generatedRoot.StartsWith($runtimeRepositoryRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Generated terrain must be inside the workspace: $generatedRoot"
}

$modelSource = Join-Path $generatedRoot "drone-terrain.xml"
$hfieldSource = Join-Path $generatedRoot "terrain.hfield"
$browserGridSource = Join-Path $generatedRoot "terrain-grid.json"
$manifestSource = Join-Path $generatedRoot "terrain-manifest.json"
$modelDirectory = Join-Path $paths.ScenarioRoot "config\drone\mujoco-shibuya-api-1"
$modelDestination = Join-Path $modelDirectory "drone.xml"
$hfieldDestination = Join-Path $modelDirectory "terrain.hfield"
$browserGridDestination = Join-Path $paths.GeoViewerRoot "config\terrain-grid.json"

foreach ($item in @($modelSource, $hfieldSource, $browserGridSource, $manifestSource, $modelDirectory)) {
    if (-not (Test-Path -LiteralPath $item)) {
        throw "Phase W6 deployment prerequisite missing: $item"
    }
}
if (Get-Process -Name "hako_drone_service" -ErrorAction SilentlyContinue) {
    throw "Stop the running simulation before replacing its terrain model."
}

Copy-Item -LiteralPath $modelSource -Destination $modelDestination -Force
Copy-Item -LiteralPath $hfieldSource -Destination $hfieldDestination -Force
Copy-Item -LiteralPath $browserGridSource -Destination $browserGridDestination -Force

$deployment = [ordered]@{
    generatedAt = (Get-Date).ToString("o")
    terrainManifest = $manifestSource
    files = @(
        [ordered]@{
            source = $modelSource
            destination = $modelDestination
            sha256 = (Get-FileHash -LiteralPath $modelDestination -Algorithm SHA256).Hash
        },
        [ordered]@{
            source = $hfieldSource
            destination = $hfieldDestination
            sha256 = (Get-FileHash -LiteralPath $hfieldDestination -Algorithm SHA256).Hash
        },
        [ordered]@{
            source = $browserGridSource
            destination = $browserGridDestination
            sha256 = (Get-FileHash -LiteralPath $browserGridDestination -Algorithm SHA256).Hash
        }
    )
}
$deploymentPath = Join-Path $paths.StateRoot "phase-w6-deployment.json"
$deployment | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $deploymentPath -Encoding utf8
$deployment | ConvertTo-Json -Depth 6
