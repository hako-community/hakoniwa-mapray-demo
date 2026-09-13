[CmdletBinding()]
param(
    [string]$AirframeDatasetId = "",
    [string]$PropellerDatasetId = "",
    [int]$HttpPort = 18080,
    [int]$ReadyTimeoutSeconds = 10,
    [switch]$NoBrowser
)

$entryPoint = Join-Path $PSScriptRoot "start_mapray_drone_model_demo.ps1"
& $entryPoint @PSBoundParameters
