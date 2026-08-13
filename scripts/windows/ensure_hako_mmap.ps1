[CmdletBinding()]
param(
    [string]$CoreConfigPath = (Join-Path $env:APPDATA "hakocore-win\config\cpp_core_config.json")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $CoreConfigPath)) {
    throw "Hakoniwa Core config was not found: $CoreConfigPath"
}
$config = Get-Content -LiteralPath $CoreConfigPath -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($config.core_mmap_path)) {
    throw "core_mmap_path is not configured in: $CoreConfigPath"
}
$target = [System.IO.Path]::GetFullPath($config.core_mmap_path)
if ([System.IO.Path]::GetFileName($target.TrimEnd("\")) -ine "mmap") {
    throw "Refusing to create an unexpected Core mmap directory: $target"
}
$root = [System.IO.Path]::GetPathRoot($target)
if (-not (Test-Path -LiteralPath $root)) {
    throw "The drive for Hakoniwa mmap is unavailable: $root"
}
New-Item -ItemType Directory -Path $target -Force | Out-Null
Write-Host "Hakoniwa standard mmap directory is ready: $target"
