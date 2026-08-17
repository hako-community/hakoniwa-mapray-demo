Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-RepositoryRoot {
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
}

function Resolve-WorkspaceRoot {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [AllowNull()][string]$ConfiguredRoot
    )

    if (-not [string]::IsNullOrWhiteSpace($ConfiguredRoot)) {
        $expanded = [Environment]::ExpandEnvironmentVariables($ConfiguredRoot)
        if (-not [System.IO.Path]::IsPathRooted($expanded)) {
            $expanded = Join-Path $RepositoryRoot $expanded
        }
        return [System.IO.Path]::GetFullPath($expanded)
    }

    $componentNames = @(
        "hakoniwa-geo-viewer",
        "hakoniwa-simenv-data",
        "hakoniwa-web3d-drone"
    )
    $parentRoot = Split-Path -Parent $RepositoryRoot
    foreach ($candidate in @($RepositoryRoot, $parentRoot) | Select-Object -Unique) {
        foreach ($componentName in $componentNames) {
            if (Test-Path -LiteralPath (Join-Path $candidate $componentName) -PathType Container) {
                return [System.IO.Path]::GetFullPath($candidate)
            }
        }
    }

    # components.lock.json defines this repository as a sibling-component
    # orchestrator.  Keep that layout even before the components are cloned so
    # prerequisite errors point to the intended locations.
    if (Test-Path -LiteralPath (Join-Path $RepositoryRoot "components.lock.json") -PathType Leaf) {
        return [System.IO.Path]::GetFullPath($parentRoot)
    }
    return [System.IO.Path]::GetFullPath($RepositoryRoot)
}

function Resolve-ConfiguredPath {
    param(
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][string]$BasePath
    )

    $expanded = [Environment]::ExpandEnvironmentVariables($Value)
    $normalized = $expanded -replace "/", "\"
    if (-not [System.IO.Path]::IsPathRooted($normalized)) {
        $normalized = Join-Path $BasePath $normalized
    }
    return [System.IO.Path]::GetFullPath($normalized)
}

function Get-WindowsPaths {
    param([string]$ConfigPath)

    $repoRoot = Get-RepositoryRoot
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $local = Join-Path $repoRoot "runtime\windows\config\windows.paths.local.json"
        $ConfigPath = if (Test-Path -LiteralPath $local) {
            $local
        } else {
            Join-Path $repoRoot "runtime\windows\config\windows.paths.example.json"
        }
    } elseif (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
        $ConfigPath = Join-Path $repoRoot $ConfigPath
    }

    $settings = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $configuredWorkspaceRoot = if ($settings.PSObject.Properties.Name -contains "workspaceRoot") {
        [string]$settings.workspaceRoot
    } else {
        $null
    }
    $workspaceRoot = Resolve-WorkspaceRoot -RepositoryRoot $repoRoot -ConfiguredRoot $configuredWorkspaceRoot
    $coreRoot = Resolve-ConfiguredPath -Value $settings.hakoniwaCore -BasePath $repoRoot
    $simRoot = Resolve-ConfiguredPath -Value $settings.hakoSim -BasePath $repoRoot
    $python = Resolve-ConfiguredPath -Value $settings.python -BasePath $repoRoot
    $pduRoot = if ($settings.PSObject.Properties.Name -contains "hakoPdu" -and
        -not [string]::IsNullOrWhiteSpace($settings.hakoPdu)) {
        Resolve-ConfiguredPath -Value $settings.hakoPdu -BasePath $repoRoot
    } else {
        Join-Path (Split-Path $simRoot -Parent) "hako-pdu"
    }

    $runtimeRoot = Join-Path $repoRoot "runtime\windows"
    return [pscustomobject]@{
        RuntimeRepositoryRoot = $repoRoot
        RepositoryRoot = $repoRoot
        WorkspaceRoot = $workspaceRoot
        GeoViewerRoot = Join-Path $workspaceRoot "hakoniwa-geo-viewer"
        SimenvDataRoot = Join-Path $workspaceRoot "hakoniwa-simenv-data"
        Web3dDroneRoot = Join-Path $workspaceRoot "hakoniwa-web3d-drone"
        PduBridgeCoreRoot = Join-Path $workspaceRoot "hakoniwa-pdu-bridge-core"
        ConfigPath = [System.IO.Path]::GetFullPath($ConfigPath)
        CoreRoot = $coreRoot
        CoreBin = Join-Path $coreRoot "bin"
        CoreLib = Join-Path $coreRoot "lib"
        CorePython = Join-Path $coreRoot "lib\py"
        SimRoot = $simRoot
        SimBin = Join-Path $simRoot "bin"
        HakoPduRoot = $pduRoot
        HakoPduOffset = Join-Path $pduRoot "offset"
        Python = $python
        RuntimeRoot = $runtimeRoot
        RuntimeConfigRoot = Join-Path $runtimeRoot "config"
        MaprayEnvFile = Join-Path $runtimeRoot "config\.env"
        ScenarioRoot = Join-Path $runtimeRoot "scenarios\shibuya"
        MmapRoot = Join-Path $runtimeRoot "mmap"
        LogsRoot = Join-Path $runtimeRoot "logs"
        StateRoot = Join-Path $runtimeRoot "state"
        CoreConfig = Join-Path $runtimeRoot "config\cpp_core_config.local.json"
    }
}

function Assert-PathIsWorkspaceOwned {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RepositoryRoot
    )
    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd("\")
    $root = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd("\")
    if (-not $full.StartsWith($root + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to modify a path outside the workspace: $full"
    }
}

function Set-HakoChildEnvironment {
    param([Parameter(Mandatory)]$Paths)

    $env:HAKO_CONFIG_PATH = $Paths.CoreConfig
    $env:HAKO_BINARY_PATH = $Paths.HakoPduOffset
    $env:HAKO_CORE_LIB_PATH = $Paths.CoreLib
    $env:PYTHONPATH = @($Paths.CorePython, $env:PYTHONPATH) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique |
        Join-String -Separator ([System.IO.Path]::PathSeparator)
    $env:PATH = @($Paths.SimBin, $Paths.CoreBin, $env:PATH) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique |
        Join-String -Separator ([System.IO.Path]::PathSeparator)
}
