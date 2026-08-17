param(
    [string]$VenvPath = "",
    [string]$PythonExe = "python"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")
$paths = Get-WindowsPaths
$runtimeRepositoryRoot = $paths.RepositoryRoot
if ([string]::IsNullOrWhiteSpace($VenvPath)) {
    $VenvPath = Join-Path $paths.RuntimeRoot ".venv-city"
}
elseif (-not [System.IO.Path]::IsPathRooted($VenvPath)) {
    $VenvPath = Join-Path $runtimeRepositoryRoot $VenvPath
}

$requirements = Join-Path $paths.SimenvDataRoot "requirements-city-pipeline.txt"
if (-not (Test-Path -LiteralPath $requirements -PathType Leaf)) {
    throw "Requirements file not found: $requirements"
}

if (-not (Test-Path -LiteralPath $VenvPath -PathType Container)) {
    & $PythonExe -m venv $VenvPath
    if ($LASTEXITCODE -ne 0) { throw "Failed to create venv: $VenvPath" }
}

$venvPython = Join-Path $VenvPath "Scripts\python.exe"
& $venvPython -m pip --version
if ($LASTEXITCODE -ne 0) { throw "pip is not usable in the city pipeline venv" }
& $venvPython -m pip install -r $requirements
if ($LASTEXITCODE -ne 0) { throw "Failed to install city pipeline requirements" }

Write-Output "City pipeline venv is ready: $venvPython"
