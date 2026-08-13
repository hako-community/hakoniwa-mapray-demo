Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-RepositoryRoot {
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
}

function Resolve-ConfiguredPath {
    param([Parameter(Mandatory)][string]$Value)
    $expanded = [Environment]::ExpandEnvironmentVariables($Value)
    return [System.IO.Path]::GetFullPath(($expanded -replace "/", "\"))
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
    $coreRoot = Resolve-ConfiguredPath $settings.hakoniwaCore
    $simRoot = Resolve-ConfiguredPath $settings.hakoSim
    $python = Resolve-ConfiguredPath $settings.python
    $pduRoot = if ($settings.PSObject.Properties.Name -contains "hakoPdu" -and
        -not [string]::IsNullOrWhiteSpace($settings.hakoPdu)) {
        Resolve-ConfiguredPath $settings.hakoPdu
    } else {
        Join-Path (Split-Path $simRoot -Parent) "hako-pdu"
    }

    $runtimeRoot = Join-Path $repoRoot "runtime\windows"
    return [pscustomobject]@{
        RepositoryRoot = $repoRoot
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
