[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string]$BlenderPath = "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe",
    [string]$OutputRoot,
    [string]$ValidatorPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$paths = Get-WindowsPaths -ConfigPath $ConfigPath
$scriptPath = [System.IO.Path]::GetFullPath(
    (Join-Path $paths.RepositoryRoot "tools\blender\export_mapray_gltf.py")
)
$sourceRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $paths.Web3dDroneRoot "assets\models")
)
$licensePath = Join-Path $sourceRoot "origin-01-LICENSE.txt"
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $paths.RuntimeRoot "generated\mapray-model-phase0"
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
$runtimePrefix = $paths.RuntimeRoot.TrimEnd("\") + "\"
if (-not $OutputRoot.StartsWith($runtimePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputRoot must stay below the demo runtime directory: $OutputRoot"
}

foreach ($required in @($BlenderPath, $scriptPath, $sourceRoot, $licensePath)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required path is missing: $required"
    }
}

& $BlenderPath `
    --background `
    --factory-startup `
    --python $scriptPath `
    -- `
    --source-root $sourceRoot `
    --output-root $OutputRoot `
    --license $licensePath
if ($LASTEXITCODE -ne 0) {
    throw "Blender model export failed with exit code $LASTEXITCODE"
}

$gltfFiles = @(
    (Join-Path $OutputRoot "airframe\origin-01-airframe.gltf"),
    (Join-Path $OutputRoot "propeller\origin-01-propeller.gltf")
)

if (-not [string]::IsNullOrWhiteSpace($ValidatorPath)) {
    $ValidatorPath = [System.IO.Path]::GetFullPath($ValidatorPath)
    if (-not (Test-Path -LiteralPath $ValidatorPath -PathType Leaf)) {
        throw "glTF Validator is missing: $ValidatorPath"
    }
    $validationRoot = Join-Path $OutputRoot "validation"
    New-Item -ItemType Directory -Force -Path $validationRoot | Out-Null
    foreach ($gltfFile in $gltfFiles) {
        $reportJson = & $ValidatorPath --stdout $gltfFile
        if ($LASTEXITCODE -ne 0) {
            throw "glTF Validator failed for $gltfFile with exit code $LASTEXITCODE"
        }
        $report = $reportJson | ConvertFrom-Json
        if ([int]$report.issues.numErrors -ne 0) {
            throw "glTF Validator found $($report.issues.numErrors) error(s): $gltfFile"
        }
        $reportName = ([System.IO.Path]::GetFileName($gltfFile)) + ".report.json"
        $reportPath = Join-Path $validationRoot $reportName
        $reportJson | Set-Content -LiteralPath $reportPath -Encoding utf8
    }
}
else {
    Write-Warning "Khronos glTF Validator was not run. Pass -ValidatorPath to make validation mandatory."
}

[ordered]@{
    status = "pass"
    outputRoot = $OutputRoot
    manifest = Join-Path $OutputRoot "manifest.json"
    validator = if ($ValidatorPath) { $ValidatorPath } else { $null }
} | ConvertTo-Json
