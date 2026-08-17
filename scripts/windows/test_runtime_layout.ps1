[CmdletBinding()]
param(
    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$paths = Get-WindowsPaths -ConfigPath $ConfigPath
$expectedRepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
if (-not $paths.RepositoryRoot.Equals(
    $expectedRepositoryRoot,
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    throw "Runtime repository root mismatch: expected=$expectedRepositoryRoot actual=$($paths.RepositoryRoot)"
}

$required = [ordered]@{
    geoViewer = Join-Path $paths.GeoViewerRoot "src\client\index.html"
    simenvData = Join-Path $paths.SimenvDataRoot "tools\city_pipeline.py"
    web3dDrone = Join-Path $paths.Web3dDroneRoot "src\public\drone_viewer.js"
    runtimeConfig = $paths.ConfigPath
}
foreach ($item in $required.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $item.Value)) {
        throw "Runtime layout prerequisite '$($item.Key)' is missing: $($item.Value)"
    }
}

foreach ($ownedPath in @($paths.RuntimeRoot, $paths.LogsRoot, $paths.StateRoot, $paths.MmapRoot)) {
    $fullPath = [System.IO.Path]::GetFullPath($ownedPath)
    $repositoryPrefix = $paths.RepositoryRoot.TrimEnd("\") + "\"
    if (-not $fullPath.StartsWith($repositoryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Runtime-owned path escaped the runtime repository: $fullPath"
    }
}

$parseErrors = [System.Collections.Generic.List[string]]::new()
foreach ($script in Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*.ps1" -File) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $script.FullName,
        [ref]$tokens,
        [ref]$errors
    ) | Out-Null
    foreach ($error in $errors) {
        $parseErrors.Add("$($script.Name): $($error.Message)")
    }
}
if ($parseErrors.Count -gt 0) {
    throw "PowerShell parse errors:`n$($parseErrors -join "`n")"
}

$forbiddenPatterns = @(
    'Join-Path\s+\$paths\.RepositoryRoot\s+"hakoniwa-',
    '"--directory",\s*\$paths\.RepositoryRoot'
)
foreach ($pattern in $forbiddenPatterns) {
    $matches = Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*.ps1" -File |
        Select-String -Pattern $pattern
    if ($matches) {
        throw "A component/workspace path is incorrectly rooted at the runtime repository:`n$($matches -join "`n")"
    }
}

$result = [ordered]@{
    status = "pass"
    runtimeRepositoryRoot = $paths.RepositoryRoot
    workspaceRoot = $paths.WorkspaceRoot
    components = [ordered]@{
        geoViewer = $paths.GeoViewerRoot
        simenvData = $paths.SimenvDataRoot
        web3dDrone = $paths.Web3dDroneRoot
    }
    parsedPowerShellScripts = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*.ps1" -File).Count
}
$result | ConvertTo-Json -Depth 4
