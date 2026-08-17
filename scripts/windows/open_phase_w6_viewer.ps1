[CmdletBinding()]
param(
    [string]$ConfigPath,
    [ValidateSet("base", "dem", "full")]
    [string]$MaprayMode = "full"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

function Get-DotEnvValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match "^\s*(?:export\s+)?$([regex]::Escape($Name))\s*=\s*(.*)$") {
            $value = $Matches[1].Trim()
            if ($value.Length -ge 2 -and
                (($value.StartsWith('"') -and $value.EndsWith('"')) -or
                 ($value.StartsWith("'") -and $value.EndsWith("'")))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            return $value
        }
    }
    return $null
}

function Set-DotEnvValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value
    )
    # PowerShell unwraps a one-item pipeline result on assignment.  Wrap the
    # complete conditional expression so zero, one, and many lines are always
    # represented by an array under StrictMode.
    $lines = @(
        if (Test-Path -LiteralPath $Path) {
            Get-Content -LiteralPath $Path
        }
    )
    $replacement = "$Name=$Value"
    $updated = $false
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match "^\s*(?:export\s+)?$([regex]::Escape($Name))\s*=") {
            $lines[$index] = $replacement
            $updated = $true
        }
    }
    if (-not $updated) { $lines += $replacement }
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Set-Content -LiteralPath $Path -Value $lines -Encoding utf8
}

$paths = Get-WindowsPaths -ConfigPath $ConfigPath
$statePath = Join-Path $paths.StateRoot "phase-w2.json"
$maprayEnvFile = $paths.MaprayEnvFile
if (-not (Test-Path -LiteralPath $statePath)) {
    throw "Phase W6 viewer is not running. Run start_simulation.ps1 and start_web_viewer.ps1 first."
}
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
foreach ($pidValue in @([int]$state.bridgePid, [int]$state.httpPid)) {
    if (-not (Get-Process -Id $pidValue -ErrorAction SilentlyContinue)) {
        throw "Phase W6 viewer state is stale. Run stop_web_viewer.ps1, then start_web_viewer.ps1."
    }
}

$apiKey = Get-DotEnvValue -Path $maprayEnvFile -Name "MAPRAY_API_KEY"
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    $secureKey = Read-Host "Mapray API Key (初回のみ .env に保存)" -AsSecureString
    $keyPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
    try {
        $apiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyPointer)
        if ([string]::IsNullOrWhiteSpace($apiKey)) {
            throw "Mapray API Key was empty."
        }
        if ($apiKey -match "[`r`n]") {
            throw "Mapray API Key contains a newline."
        }
        Set-DotEnvValue -Path $maprayEnvFile -Name "MAPRAY_API_KEY" -Value $apiKey.Trim()
        Write-Host "Saved Mapray API Key to runtime/windows/config/.env (git ignored)."
    } finally {
        if ($keyPointer -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keyPointer)
        }
        $secureKey.Dispose()
        $apiKey = $null
    }
}

$cacheBust = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$separator = if ($state.httpUri.Contains("?")) { "&" } else { "?" }
$url = "$($state.httpUri)$($separator)maprayMode=$MaprayMode&v=$cacheBust"
Start-Process $url
Write-Host "Opened Phase W6 viewer (Mapray mode: $MaprayMode). API Key is loaded from the local .env endpoint."
