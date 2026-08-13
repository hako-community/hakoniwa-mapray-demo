[CmdletBinding()]
param(
    [string]$ConfigPath,
    [double]$DurationSeconds = 5.0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$paths = Get-WindowsPaths -ConfigPath $ConfigPath
Set-HakoChildEnvironment -Paths $paths
$monitor = Join-Path $PSScriptRoot "monitor_phase_w1.py"
$pduConfig = Join-Path $paths.ScenarioRoot "config\pdudef\webavatar.json"
$report = Join-Path $paths.LogsRoot "phase-w6-terrain-probe.json"

& $paths.Python $monitor --config $pduConfig --duration $DurationSeconds --interval 0.01 --report $report
if ($LASTEXITCODE -ne 0) {
    throw "Phase W6 terrain probe failed with exit code $LASTEXITCODE"
}
Get-Content -LiteralPath $report -Raw
