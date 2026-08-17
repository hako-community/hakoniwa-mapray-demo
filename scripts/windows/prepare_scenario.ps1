[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$Refresh
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$paths = Get-WindowsPaths -ConfigPath $ConfigPath
$sourceRoot = $paths.SimBin
$sourceFiles = [ordered]@{
    "config\drone\mujoco-shibuya-api-1\drone_config_0.json" = "config\drone\mujoco-shibuya-api-1\drone_config_0.json"
    "config\drone\mujoco-shibuya-api-1\drone.xml" = "config\drone\mujoco-shibuya-api-1\drone.xml"
    "config\controller\param-api-mixer-mujoco-shibuya.txt" = "config\controller\param-api-mixer-mujoco-shibuya.txt"
    "config\pdudef\webavatar.json" = "config\pdudef\webavatar.json"
}

$required = @(
    $paths.SimBin,
    (Join-Path $paths.SimBin "hako_drone_service.exe"),
    (Join-Path $paths.SimBin "mujoco.dll"),
    (Join-Path $paths.CoreBin "hako-cmd.exe"),
    $paths.HakoPduOffset,
    $paths.Python
)
foreach ($item in $required) {
    if (-not (Test-Path -LiteralPath $item)) {
        throw "Required Phase W1 path was not found: $item"
    }
}

$mujocoDll = Join-Path $paths.SimBin "mujoco.dll"
$mujocoVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($mujocoDll).ProductVersion
if (-not $mujocoVersion.StartsWith("3.7")) {
    throw "hakoSim runtime MuJoCo must be 3.7.x, found '$mujocoVersion' at $mujocoDll"
}

New-Item -ItemType Directory -Force -Path $paths.ScenarioRoot, $paths.MmapRoot, $paths.LogsRoot, $paths.StateRoot | Out-Null
foreach ($relative in $sourceFiles.Keys) {
    $source = Join-Path $sourceRoot $sourceFiles[$relative]
    $destination = Join-Path $paths.ScenarioRoot $relative
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Scenario source file was not found: $source"
    }
    $parent = Split-Path $destination -Parent
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    if ($Refresh -or -not (Test-Path -LiteralPath $destination)) {
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }
}
New-Item -ItemType Directory -Force -Path (Join-Path $paths.ScenarioRoot "logs") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $paths.ScenarioRoot "config\drone\mujoco-shibuya-api-1\logs") | Out-Null

$droneConfigPath = Join-Path $paths.ScenarioRoot "config\drone\mujoco-shibuya-api-1\drone_config_0.json"
$droneConfig = Get-Content -LiteralPath $droneConfigPath -Raw | ConvertFrom-Json
$droneConfig.simulation.logOutputDirectory = "logs"
$droneConfig.components.droneDynamics.mujoco.modelPath = "config/drone/mujoco-shibuya-api-1/drone.xml"
$droneConfig.controller.paramFilePath = "config/controller/param-api-mixer-mujoco-shibuya.txt"
$droneConfig | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $droneConfigPath -Encoding utf8

$coreConfig = [ordered]@{
    shm_type = "mmap"
    core_mmap_path = $paths.MmapRoot
    asset_timeout_usec = 600000000
}
$coreConfig | ConvertTo-Json | Set-Content -LiteralPath $paths.CoreConfig -Encoding utf8

$manifestFiles = foreach ($relative in $sourceFiles.Keys) {
    $destination = Join-Path $paths.ScenarioRoot $relative
    $source = Join-Path $sourceRoot $sourceFiles[$relative]
    [ordered]@{
        relativePath = $relative
        sourceBase = "hakoSim"
        sourcePath = [System.IO.Path]::GetRelativePath($paths.SimRoot, $source).Replace("\", "/")
        sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
    }
}
$manifest = [ordered]@{
    generatedAt = (Get-Date).ToString("o")
    pathBase = "runtimeRepository"
    scenarioRoot = [System.IO.Path]::GetRelativePath($paths.RepositoryRoot, $paths.ScenarioRoot).Replace("\", "/")
    coreConfig = [System.IO.Path]::GetRelativePath($paths.RepositoryRoot, $paths.CoreConfig).Replace("\", "/")
    mmapRoot = [System.IO.Path]::GetRelativePath($paths.RepositoryRoot, $paths.MmapRoot).Replace("\", "/")
    runtime = [ordered]@{
        pathBase = "hakoSim"
        executable = [System.IO.Path]::GetRelativePath($paths.SimRoot, (Join-Path $paths.SimBin "hako_drone_service.exe")).Replace("\", "/")
        mujocoDll = [System.IO.Path]::GetRelativePath($paths.SimRoot, $mujocoDll).Replace("\", "/")
        mujocoVersion = $mujocoVersion
    }
    files = @($manifestFiles)
}
$manifestPath = Join-Path $paths.ScenarioRoot "scenario-manifest.json"
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding utf8

Write-Host "Phase W1 scenario prepared."
Write-Host "  Scenario : $($paths.ScenarioRoot)"
Write-Host "  Core mmap: $($paths.MmapRoot)"
Write-Host "  MuJoCo   : $mujocoDll ($mujocoVersion)"
Write-Host "  Manifest : $manifestPath"

