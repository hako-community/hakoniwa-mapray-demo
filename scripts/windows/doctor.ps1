[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string]$ReportPath,
    [switch]$Strict
)

$ErrorActionPreference = "Stop"
$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$DefaultLocalConfig = Join-Path $RepoRoot "runtime\windows\config\windows.paths.local.json"
$DefaultExampleConfig = Join-Path $RepoRoot "runtime\windows\config\windows.paths.example.json"
$DefaultReportPath = Join-Path $RepoRoot "runtime\windows\logs\doctor-report.json"

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = if (Test-Path -LiteralPath $DefaultLocalConfig -PathType Leaf) {
        $DefaultLocalConfig
    }
    else {
        $DefaultExampleConfig
    }
}
elseif (-not [IO.Path]::IsPathRooted($ConfigPath)) {
    $ConfigPath = Join-Path $RepoRoot $ConfigPath
}
$ConfigPath = [IO.Path]::GetFullPath($ConfigPath)

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = $DefaultReportPath
}
elseif (-not [IO.Path]::IsPathRooted($ReportPath)) {
    $ReportPath = Join-Path $RepoRoot $ReportPath
}
$ReportPath = [IO.Path]::GetFullPath($ReportPath)

$Checks = [Collections.Generic.List[object]]::new()
$Details = [ordered]@{}

function Add-Check {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet("PASS", "WARN", "FAIL", "INFO")][string]$Status,
        [Parameter(Mandatory)][ValidateSet("required", "optional", "information")][string]$Severity,
        [Parameter(Mandatory)][string]$Message,
        [string]$Path = ""
    )

    $Checks.Add([pscustomobject][ordered]@{
        name = $Name
        status = $Status
        severity = $Severity
        message = $Message
        path = $Path
    }) | Out-Null

    $color = switch ($Status) {
        "PASS" { "Green" }
        "WARN" { "Yellow" }
        "FAIL" { "Red" }
        default { "Cyan" }
    }
    Write-Host ("[{0,-4}] {1}: {2}" -f $Status, $Name, $Message) -ForegroundColor $color
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        Write-Host ("       {0}" -f $Path) -ForegroundColor DarkGray
    }
}

function Expand-ConfiguredPath {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }
    $expanded = [Environment]::ExpandEnvironmentVariables($Value)
    if (-not [IO.Path]::IsPathRooted($expanded)) {
        $expanded = Join-Path $RepoRoot $expanded
    }
    return [IO.Path]::GetFullPath($expanded)
}

function Test-RequiredFile {
    param([string]$Name, [string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Add-Check -Name $Name -Status PASS -Severity required -Message "File found." -Path $Path
        return $true
    }
    Add-Check -Name $Name -Status FAIL -Severity required -Message "Required file was not found." -Path $Path
    return $false
}

function Test-RequiredDirectory {
    param([string]$Name, [string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Container) {
        Add-Check -Name $Name -Status PASS -Severity required -Message "Directory found." -Path $Path
        return $true
    }
    Add-Check -Name $Name -Status FAIL -Severity required -Message "Required directory was not found." -Path $Path
    return $false
}

function Get-PeMachine {
    param([string]$Path)

    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $reader = [IO.BinaryReader]::new($stream)
        if ($reader.ReadUInt16() -ne 0x5A4D) {
            throw "Not a PE file (missing MZ header)."
        }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        if ($peOffset -lt 0 -or $peOffset -gt ($stream.Length - 6)) {
            throw "Invalid PE header offset."
        }
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) {
            throw "Not a PE file (missing PE signature)."
        }
        $machine = $reader.ReadUInt16()
        if ($machine -eq 0x8664) { return "x64" }
        if ($machine -eq 0x014C) { return "x86" }
        if ($machine -eq 0xAA64) { return "ARM64" }
        return "unknown-0x{0:X4}" -f $machine
    }
    finally {
        $stream.Dispose()
    }
}

function Test-X64Pe {
    param([string]$Name, [string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }
    try {
        $machine = Get-PeMachine -Path $Path
        if ($machine -eq "x64") {
            Add-Check -Name $Name -Status PASS -Severity required -Message "PE architecture is x64." -Path $Path
        }
        else {
            Add-Check -Name $Name -Status FAIL -Severity required -Message "Expected x64 but found $machine." -Path $Path
        }
    }
    catch {
        Add-Check -Name $Name -Status FAIL -Severity required -Message $_.Exception.Message -Path $Path
    }
}

function Invoke-PythonProbe {
    param(
        [string]$PythonExe,
        [string]$Code,
        [string[]]$Arguments = @()
    )

    try {
        $output = & $PythonExe -c $Code @Arguments 2>&1
        $exitCode = $LASTEXITCODE
        return [pscustomobject]@{
            success = ($exitCode -eq 0)
            exitCode = $exitCode
            output = (($output | Out-String).Trim())
        }
    }
    catch {
        return [pscustomobject]@{
            success = $false
            exitCode = -1
            output = $_.Exception.Message
        }
    }
}

Write-Host "Hakoniwa Mapray Windows Doctor" -ForegroundColor White
Write-Host "Repository: $RepoRoot" -ForegroundColor DarkGray
Write-Host "Config:     $ConfigPath" -ForegroundColor DarkGray
Write-Host "Report:     $ReportPath" -ForegroundColor DarkGray
Write-Host ""

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    Add-Check -Name "Path configuration" -Status FAIL -Severity required -Message "Configuration file was not found." -Path $ConfigPath
    $config = [pscustomobject]@{}
}
else {
    try {
        $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        Add-Check -Name "Path configuration" -Status PASS -Severity required -Message "Configuration loaded." -Path $ConfigPath
    }
    catch {
        Add-Check -Name "Path configuration" -Status FAIL -Severity required -Message ("Invalid JSON: " + $_.Exception.Message) -Path $ConfigPath
        $config = [pscustomobject]@{}
    }
}

$coreRoot = Expand-ConfiguredPath $config.hakoniwaCore
$simRoot = Expand-ConfiguredPath $config.hakoSim
$pythonExe = Expand-ConfiguredPath $config.python
$mapraySdk = Expand-ConfiguredPath $config.mapraySdk

if ([string]::IsNullOrWhiteSpace($pythonExe) -or -not (Test-Path -LiteralPath $pythonExe -PathType Leaf)) {
    $pythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($null -ne $pythonCommand) {
        $pythonExe = $pythonCommand.Source
    }
}

if ([string]::IsNullOrWhiteSpace($coreRoot)) {
    Add-Check -Name "Hakoniwa Core root" -Status FAIL -Severity required -Message "hakoniwaCore is empty in the path configuration."
}
else {
    Test-RequiredDirectory -Name "Hakoniwa Core root" -Path $coreRoot | Out-Null
}

if ([string]::IsNullOrWhiteSpace($simRoot)) {
    Add-Check -Name "hakoSim root" -Status FAIL -Severity required -Message "hakoSim is empty in the path configuration."
}
else {
    Test-RequiredDirectory -Name "hakoSim root" -Path $simRoot | Out-Null
}

$coreBin = if ($coreRoot) { Join-Path $coreRoot "bin" } else { "" }
$corePython = if ($coreRoot) { Join-Path $coreRoot "lib\py" } else { "" }
$simBin = if ($simRoot) { Join-Path $simRoot "bin" } else { "" }
$hakoCmd = if ($coreBin) { Join-Path $coreBin "hako-cmd.exe" } else { "" }
$shakocDll = if ($coreBin) { Join-Path $coreBin "shakoc.dll" } else { "" }
$hakopyPyd = if ($corePython) { Join-Path $corePython "hakopy.pyd" } else { "" }
$droneService = if ($simBin) { Join-Path $simBin "hako_drone_service.exe" } else { "" }
$mujocoDll = if ($simBin) { Join-Path $simBin "mujoco.dll" } else { "" }
$shibuyaConfigDir = if ($simBin) { Join-Path $simBin "config\drone\mujoco-shibuya-api-1" } else { "" }
$shibuyaConfig = if ($shibuyaConfigDir) { Join-Path $shibuyaConfigDir "drone_config_0.json" } else { "" }
$shibuyaMjcf = if ($shibuyaConfigDir) { Join-Path $shibuyaConfigDir "drone.xml" } else { "" }
$controllerParams = if ($simBin) { Join-Path $simBin "config\controller\param-api-mixer-mujoco-shibuya.txt" } else { "" }

foreach ($item in @(
    @{ Name = "Hakoniwa command"; Path = $hakoCmd },
    @{ Name = "Hakoniwa runtime DLL"; Path = $shakocDll },
    @{ Name = "Hakoniwa Python module"; Path = $hakopyPyd },
    @{ Name = "Drone service"; Path = $droneService },
    @{ Name = "MuJoCo runtime DLL"; Path = $mujocoDll },
    @{ Name = "Shibuya drone config"; Path = $shibuyaConfig },
    @{ Name = "Shibuya MJCF"; Path = $shibuyaMjcf },
    @{ Name = "Shibuya controller parameters"; Path = $controllerParams }
)) {
    if (-not [string]::IsNullOrWhiteSpace($item.Path)) {
        Test-RequiredFile -Name $item.Name -Path $item.Path | Out-Null
    }
}

if ([string]::IsNullOrWhiteSpace($pythonExe)) {
    Add-Check -Name "Python executable" -Status FAIL -Severity required -Message "Python was not found in the configured path or PATH."
}
else {
    Test-RequiredFile -Name "Python executable" -Path $pythonExe | Out-Null
}

if ([Environment]::Is64BitOperatingSystem) {
    Add-Check -Name "Windows architecture" -Status PASS -Severity required -Message "64-bit Windows detected."
}
else {
    Add-Check -Name "Windows architecture" -Status FAIL -Severity required -Message "64-bit Windows is required."
}

foreach ($item in @(
    @{ Name = "hako-cmd architecture"; Path = $hakoCmd },
    @{ Name = "shakoc architecture"; Path = $shakocDll },
    @{ Name = "hakopy architecture"; Path = $hakopyPyd },
    @{ Name = "hako_drone_service architecture"; Path = $droneService },
    @{ Name = "mujoco.dll architecture"; Path = $mujocoDll },
    @{ Name = "Python architecture"; Path = $pythonExe }
)) {
    if (-not [string]::IsNullOrWhiteSpace($item.Path)) {
        Test-X64Pe -Name $item.Name -Path $item.Path
    }
}

if (Test-Path -LiteralPath $mujocoDll -PathType Leaf) {
    $mujocoFileVersion = (Get-Item -LiteralPath $mujocoDll).VersionInfo.FileVersion
    $Details.mujocoRuntimeDllVersion = $mujocoFileVersion
    Add-Check -Name "MuJoCo runtime version" -Status INFO -Severity information -Message ("hakoSim DLL version: " + $mujocoFileVersion) -Path $mujocoDll
}

$browserCandidates = @(
    (Join-Path ${env:ProgramFiles(x86)} "Microsoft\Edge\Application\msedge.exe"),
    (Join-Path $env:ProgramFiles "Microsoft\Edge\Application\msedge.exe"),
    (Join-Path $env:ProgramFiles "Google\Chrome\Application\chrome.exe"),
    (Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe")
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
$browsers = @($browserCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
if ($browsers.Count -gt 0) {
    Add-Check -Name "Web browser" -Status PASS -Severity required -Message ("Found: " + (($browsers | ForEach-Object { Split-Path $_ -Leaf }) -join ", ")) -Path ($browsers -join "; ")
}
else {
    Add-Check -Name "Web browser" -Status FAIL -Severity required -Message "Neither Microsoft Edge nor Google Chrome was found in standard locations."
}
$Details.browsers = $browsers

$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
$vsInstall = $null
$clExe = $null
if (Test-Path -LiteralPath $vswhere -PathType Leaf) {
    $vsInstall = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
    if ($vsInstall) {
        $clExe = Get-ChildItem -LiteralPath (Join-Path $vsInstall "VC\Tools\MSVC") -Recurse -Filter cl.exe -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\bin\\Hostx64\\x64\\cl\.exe$' } |
            Sort-Object FullName -Descending |
            Select-Object -First 1 -ExpandProperty FullName
    }
}
if ($clExe) {
    Add-Check -Name "Visual Studio C++ x64" -Status PASS -Severity required -Message "MSVC x64 compiler found." -Path $clExe
}
else {
    Add-Check -Name "Visual Studio C++ x64" -Status FAIL -Severity required -Message "Visual Studio with the MSVC x64 toolset was not found."
}
$Details.visualStudio = [ordered]@{ installationPath = $vsInstall; clExe = $clExe }

foreach ($port in @(18080, 8001, 8765)) {
    try {
        $listeners = @([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners() |
            Where-Object { $_.Port -eq $port })
        if ($listeners.Count -eq 0) {
            Add-Check -Name "TCP port $port" -Status PASS -Severity required -Message "Port is available."
        }
        else {
            Add-Check -Name "TCP port $port" -Status WARN -Severity optional -Message ("Port is already in use at " + (($listeners | ForEach-Object { $_.ToString() }) -join ", "))
        }
    }
    catch {
        Add-Check -Name "TCP port $port" -Status WARN -Severity optional -Message ("Could not inspect port: " + $_.Exception.Message)
    }
}

if (Test-Path -LiteralPath $shibuyaConfig -PathType Leaf) {
    try {
        $droneConfig = Get-Content -LiteralPath $shibuyaConfig -Raw | ConvertFrom-Json
        $moduleName = [string]$droneConfig.controller.moduleName
        $moduleDirectory = [string]$droneConfig.controller.moduleDirectory
        $Details.shibuyaController = [ordered]@{
            moduleName = $moduleName
            moduleDirectory = $moduleDirectory
            moduleDirectoryPolicy = "legacy-metadata-not-required-by-phase-w0"
        }
        Add-Check -Name "Controller selection" -Status INFO -Severity information -Message ("moduleName='$moduleName'; the installed hako_drone_service.exe is the required runtime executable.") -Path $droneService
        if (-not [string]::IsNullOrWhiteSpace($moduleDirectory)) {
            Add-Check -Name "Legacy controller directory" -Status INFO -Severity information -Message "moduleDirectory is retained as legacy development metadata and is not treated as a missing Phase W0 runtime file." -Path $moduleDirectory
        }
    }
    catch {
        Add-Check -Name "Shibuya controller config" -Status FAIL -Severity required -Message ("Could not parse controller settings: " + $_.Exception.Message) -Path $shibuyaConfig
    }
}

if (-not [string]::IsNullOrWhiteSpace($pythonExe) -and (Test-Path -LiteralPath $pythonExe -PathType Leaf)) {
    $originalPath = $env:PATH
    $originalPythonPath = $env:PYTHONPATH
    try {
        $env:PATH = (($simBin, $coreBin, $originalPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ";")
        $env:PYTHONPATH = (($corePython, $originalPythonPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ";")

        $pythonProbe = Invoke-PythonProbe -PythonExe $pythonExe -Code "import json, platform, struct, sys; print(json.dumps({'version': sys.version.split()[0], 'bits': struct.calcsize('P') * 8, 'platform': platform.platform()}))"
        if ($pythonProbe.success) {
            $Details.python = $pythonProbe.output | ConvertFrom-Json
            Add-Check -Name "Python runtime" -Status PASS -Severity required -Message ("Python " + $Details.python.version + ", " + $Details.python.bits + "-bit") -Path $pythonExe
        }
        else {
            Add-Check -Name "Python runtime" -Status FAIL -Severity required -Message $pythonProbe.output -Path $pythonExe
        }

        $hakopyProbe = Invoke-PythonProbe -PythonExe $pythonExe -Code "import hakopy; print('hakopy import OK')"
        if ($hakopyProbe.success) {
            Add-Check -Name "Python import: hakopy" -Status PASS -Severity required -Message $hakopyProbe.output -Path $hakopyPyd
        }
        else {
            Add-Check -Name "Python import: hakopy" -Status FAIL -Severity required -Message $hakopyProbe.output -Path $hakopyPyd
        }

        $mujocoProbe = Invoke-PythonProbe -PythonExe $pythonExe -Code "import mujoco; print(mujoco.__version__)"
        if ($mujocoProbe.success) {
            $Details.mujocoPythonVersion = $mujocoProbe.output
            Add-Check -Name "Python import: mujoco" -Status PASS -Severity required -Message ("MuJoCo Python " + $mujocoProbe.output)
        }
        else {
            Add-Check -Name "Python import: mujoco" -Status FAIL -Severity required -Message $mujocoProbe.output
        }

        $pyprojProbe = Invoke-PythonProbe -PythonExe $pythonExe -Code "import pyproj; print(pyproj.__version__)"
        if ($pyprojProbe.success) {
            $Details.pyprojVersion = $pyprojProbe.output
            Add-Check -Name "Python import: pyproj" -Status PASS -Severity optional -Message ("pyproj " + $pyprojProbe.output)
        }
        else {
            Add-Check -Name "Python import: pyproj" -Status WARN -Severity optional -Message "pyproj is not installed. It is not needed until the geographic conversion phase; install it with: python -m pip install pyproj"
        }

        if ($mujocoProbe.success -and (Test-Path -LiteralPath $shibuyaMjcf -PathType Leaf)) {
            $mjcfCode = @'
import json
import sys
import time
import mujoco

path = sys.argv[1]
started = time.perf_counter()
model = mujoco.MjModel.from_xml_path(path)

def name(obj_type, index):
    return mujoco.mj_id2name(model, obj_type, index)

body_names = [name(mujoco.mjtObj.mjOBJ_BODY, i) for i in range(model.nbody)]
geom_names = [name(mujoco.mjtObj.mjOBJ_GEOM, i) for i in range(model.ngeom)]
building_geom_ids = [i for i, value in enumerate(geom_names) if value and value.startswith("geom_bldg_")]
building_body_ids = [i for i, value in enumerate(body_names) if value and value.startswith("body_bldg_")]
required_bodies = ["drone_base", "arm1", "arm2", "arm3", "arm4", "prop1", "prop2", "prop3", "prop4"]

drone_root = mujoco.mj_name2id(model, mujoco.mjtObj.mjOBJ_BODY, "drone_base")
drone_bodies = set()
if drone_root >= 0:
    drone_bodies.add(drone_root)
    changed = True
    while changed:
        changed = False
        for body_id in range(model.nbody):
            if body_id not in drone_bodies and int(model.body_parentid[body_id]) in drone_bodies:
                drone_bodies.add(body_id)
                changed = True
drone_geom_ids = [i for i in range(model.ngeom) if int(model.geom_bodyid[i]) in drone_bodies]

def compatible(a, b):
    return bool(
        (int(model.geom_contype[a]) & int(model.geom_conaffinity[b]))
        or (int(model.geom_contype[b]) & int(model.geom_conaffinity[a]))
    )

compatible_buildings = sum(
    1 for building_id in building_geom_ids
    if any(compatible(building_id, drone_id) for drone_id in drone_geom_ids)
)

def masks(indices):
    return sorted({
        (int(model.geom_contype[i]), int(model.geom_conaffinity[i]))
        for i in indices
    })

result = {
    "path": path,
    "load_seconds": round(time.perf_counter() - started, 3),
    "nbody": model.nbody,
    "ngeom": model.ngeom,
    "njnt": model.njnt,
    "nq": model.nq,
    "nv": model.nv,
    "building_body_count": len(building_body_ids),
    "building_geom_count": len(building_geom_ids),
    "building_geom_sample": [geom_names[i] for i in building_geom_ids[:5]],
    "building_contact_masks": masks(building_geom_ids),
    "drone_body_count": len(drone_bodies),
    "drone_geom_count": len(drone_geom_ids),
    "drone_contact_masks": masks(drone_geom_ids),
    "building_geoms_collision_compatible_with_drone": compatible_buildings,
    "required_bodies": {item: item in body_names for item in required_bodies},
}
print(json.dumps(result))
'@
            $mjcfProbe = Invoke-PythonProbe -PythonExe $pythonExe -Code $mjcfCode -Arguments @($shibuyaMjcf)
            if ($mjcfProbe.success) {
                try {
                    $mjcfDetails = $mjcfProbe.output | ConvertFrom-Json
                    $Details.shibuyaMjcf = $mjcfDetails
                    Add-Check -Name "Shibuya MJCF load" -Status PASS -Severity required -Message ("Loaded in {0}s: nbody={1}, ngeom={2}." -f $mjcfDetails.load_seconds, $mjcfDetails.nbody, $mjcfDetails.ngeom) -Path $shibuyaMjcf
                    if ($mjcfDetails.building_geom_count -gt 0) {
                        Add-Check -Name "Shibuya building geoms" -Status PASS -Severity required -Message ("Found {0} building geoms and {1} building bodies." -f $mjcfDetails.building_geom_count, $mjcfDetails.building_body_count)
                    }
                    else {
                        Add-Check -Name "Shibuya building geoms" -Status FAIL -Severity required -Message "No geom_bldg_* geometry was found."
                    }
                    $missingBodies = @($mjcfDetails.required_bodies.psobject.Properties | Where-Object { -not $_.Value } | ForEach-Object { $_.Name })
                    if ($missingBodies.Count -eq 0) {
                        Add-Check -Name "Required drone bodies" -Status PASS -Severity required -Message "drone_base, four arms, and four propeller bodies are present."
                    }
                    else {
                        Add-Check -Name "Required drone bodies" -Status FAIL -Severity required -Message ("Missing: " + ($missingBodies -join ", "))
                    }
                    if ($mjcfDetails.building_geoms_collision_compatible_with_drone -eq $mjcfDetails.building_geom_count) {
                        Add-Check -Name "Building/drone contact bits" -Status PASS -Severity required -Message ("All {0} building geoms are collision-compatible with a drone geom." -f $mjcfDetails.building_geom_count)
                    }
                    elseif ($mjcfDetails.building_geoms_collision_compatible_with_drone -gt 0) {
                        Add-Check -Name "Building/drone contact bits" -Status WARN -Severity optional -Message ("{0}/{1} building geoms are collision-compatible." -f $mjcfDetails.building_geoms_collision_compatible_with_drone, $mjcfDetails.building_geom_count)
                    }
                    else {
                        Add-Check -Name "Building/drone contact bits" -Status FAIL -Severity required -Message "No building geom is collision-compatible with the drone geoms."
                    }
                }
                catch {
                    Add-Check -Name "Shibuya MJCF report" -Status FAIL -Severity required -Message ("Could not parse probe output: " + $_.Exception.Message)
                }
            }
            else {
                Add-Check -Name "Shibuya MJCF load" -Status FAIL -Severity required -Message $mjcfProbe.output -Path $shibuyaMjcf
            }
        }
    }
    finally {
        $env:PATH = $originalPath
        $env:PYTHONPATH = $originalPythonPath
    }
}

if ([string]::IsNullOrWhiteSpace($mapraySdk)) {
    Add-Check -Name "Mapray SDK" -Status INFO -Severity information -Message "No local Mapray SDK is configured. It is not required for Phase W0."
}
elseif (Test-Path -LiteralPath $mapraySdk) {
    Add-Check -Name "Mapray SDK" -Status PASS -Severity optional -Message "Configured Mapray SDK path exists." -Path $mapraySdk
}
else {
    Add-Check -Name "Mapray SDK" -Status WARN -Severity optional -Message "Configured Mapray SDK path does not exist." -Path $mapraySdk
}

$failCount = @($Checks | Where-Object { $_.status -eq "FAIL" }).Count
$warnCount = @($Checks | Where-Object { $_.status -eq "WARN" }).Count
$passCount = @($Checks | Where-Object { $_.status -eq "PASS" }).Count
$overallStatus = if ($failCount -gt 0) { "FAIL" } elseif ($warnCount -gt 0) { "PASS_WITH_WARNINGS" } else { "PASS" }

$report = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString("o")
    phase = "W0"
    overallStatus = $overallStatus
    repositoryRoot = $RepoRoot
    configPath = $ConfigPath
    configuredPaths = [ordered]@{
        hakoniwaCore = $coreRoot
        hakoSim = $simRoot
        python = $pythonExe
        mapraySdk = $mapraySdk
    }
    summary = [ordered]@{
        pass = $passCount
        warnings = $warnCount
        failures = $failCount
    }
    checks = $Checks
    details = $Details
}

$reportDirectory = Split-Path -Parent $ReportPath
if (-not (Test-Path -LiteralPath $reportDirectory -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $reportDirectory | Out-Null
}
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $ReportPath -Encoding utf8

Write-Host ""
Write-Host ("Result: {0} (PASS={1}, WARN={2}, FAIL={3})" -f $overallStatus, $passCount, $warnCount, $failCount) -ForegroundColor $(if ($failCount -gt 0) { "Red" } elseif ($warnCount -gt 0) { "Yellow" } else { "Green" })
Write-Host "Report: $ReportPath" -ForegroundColor White

if ($failCount -gt 0) {
    exit 1
}
if ($Strict -and $warnCount -gt 0) {
    exit 2
}
exit 0
