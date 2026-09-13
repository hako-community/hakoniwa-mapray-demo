[CmdletBinding()]
param(
    [ValidateSet("model", "pin", "both")]
    [string]$RenderMode = "pin",
    [ValidateSet(1, 5, 10)]
    [int]$FleetSize = 1,
    [int]$HttpPort = 18080,
    [int]$VirtualTimeBudgetMs = 30000,
    [switch]$LifecycleTest,
    [string]$ChromePath = "C:\Program Files\Google\Chrome\Application\chrome.exe"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ChromePath -PathType Leaf)) {
    throw "Chrome executable was not found: $ChromePath"
}
$viewerUrl = "http://localhost:$HttpPort/hakoniwa-geo-viewer/src/client/mapray-drone-model.html?droneRender=$RenderMode&fleetSize=$FleetSize"
if ($LifecycleTest) { $viewerUrl += "&lifecycleTest=1" }
if ($viewerUrl -match '(?i)(api.?key|token)=') {
    throw "Secrets must not be passed in the browser E2E URL."
}
$expectedEntityCount = @{ model = 5; pin = 1; both = 6 }[$RenderMode] * $FleetSize
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("mapray-drone-e2e-" + [Guid]::NewGuid().ToString("N"))
$profilePath = Join-Path $tempRoot "profile"
$stdoutPath = Join-Path $tempRoot "dom.html"
$stderrPath = Join-Path $tempRoot "chrome.err"
$proc = $null

try {
    New-Item -ItemType Directory -Force -Path $profilePath | Out-Null
    $arguments = @(
        "--headless=new",
        "--disable-gpu",
        "--no-first-run",
        "--user-data-dir=$profilePath",
        "--dump-dom",
        "--virtual-time-budget=$VirtualTimeBudgetMs",
        $viewerUrl
    )
    $proc = Start-Process -FilePath $ChromePath -ArgumentList $arguments `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath `
        -WindowStyle Hidden -PassThru
    if (-not $proc.WaitForExit($VirtualTimeBudgetMs + 30000)) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        throw "Chrome browser E2E timed out for render mode '$RenderMode'."
    }
    $proc.WaitForExit()
    $dom = if (Test-Path -LiteralPath $stdoutPath) {
        Get-Content -LiteralPath $stdoutPath -Raw
    } else {
        ""
    }
    $diagnosticsMatch = [regex]::Match(
        $dom,
        '(?s)<script id="mapray-drone-diagnostics" type="application/json">(.*?)</script>'
    )
    $diagnostics = if ($diagnosticsMatch.Success) {
        [System.Net.WebUtility]::HtmlDecode($diagnosticsMatch.Groups[1].Value) | ConvertFrom-Json
    } else { $null }
    if ($null -eq $diagnostics -or
        $diagnostics.state -ne "ready" -or
        $diagnostics.renderMode -ne $RenderMode -or
        [int]$diagnostics.activeDroneCount -ne $FleetSize -or
        [int]$diagnostics.entityCount -ne $expectedEntityCount) {
        $chromeError = if (Test-Path -LiteralPath $stderrPath) {
            (Get-Content -LiteralPath $stderrPath -Raw).Trim()
        } else { "" }
        $actual = if ($null -eq $diagnostics) { "missing diagnostics" } else {
            "state=$($diagnostics.state), mode=$($diagnostics.renderMode), entities=$($diagnostics.entityCount), error=$($diagnostics.error)"
        }
        throw "Browser E2E did not reach the expected READY contract ($actual). Chrome: $chromeError"
    }
    if ($LifecycleTest -and $FleetSize -gt 1) {
        $expectedRemoved = [Math]::Floor($FleetSize / 2)
        if ([int]$diagnostics.createdDroneCount -lt ($FleetSize + $expectedRemoved) -or
            [int]$diagnostics.disposedDroneCount -lt $expectedRemoved) {
            throw "Browser lifecycle E2E did not observe remove/recreate: created=$($diagnostics.createdDroneCount), disposed=$($diagnostics.disposedDroneCount)"
        }
    }
    [ordered]@{
        status = "pass"
        renderMode = $RenderMode
        fleetSize = $FleetSize
        entityCount = $expectedEntityCount
        cloudDatasetRequestCount = $diagnostics.cloudDatasetRequestCount
        cloudResourceCreateCount = $diagnostics.cloudResourceCreateCount
        createdDroneCount = $diagnostics.createdDroneCount
        disposedDroneCount = $diagnostics.disposedDroneCount
        layerPerformance = $diagnostics.performance
        browserPerformance = $diagnostics.browserPerformance
        viewerUrl = $viewerUrl
    } | ConvertTo-Json
} finally {
    if ($null -ne $proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $tempRoot) {
        $resolvedTemp = (Resolve-Path -LiteralPath $tempRoot).Path
        $systemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd("\") + "\"
        if ($resolvedTemp.StartsWith($systemTemp + "mapray-drone-e2e-", [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedTemp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
