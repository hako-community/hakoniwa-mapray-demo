# Windows runtime workspace

This directory contains runtime-repository-owned configuration, generated data, and logs for the Windows-only Mapray integration. Installed files under `AppData` are treated as read-only.

Run every command from the `hakoniwa-mapray-runtime` repository root. The
runtime repository and `hakoniwa-geo-viewer`, `hakoniwa-simenv-data`, and
`hakoniwa-web3d-drone` are sibling directories. `windows.paths.local.json` can
override `workspaceRoot` when a different checkout layout is required.

## Phase W0 doctor

Run from the repository root:

```powershell
.\scripts\windows\doctor.ps1
```

The default configuration is `config/windows.paths.example.json`. It uses `%APPDATA%` and `%LOCALAPPDATA%`, so it works with the standard installer layout without embedding a user name.

For a non-standard installation, copy the example to `config/windows.paths.local.json` and edit only the local copy. The local file is ignored by Git.

```powershell
Copy-Item .\runtime\windows\config\windows.paths.example.json .\runtime\windows\config\windows.paths.local.json
```

The machine-readable result is written to `logs/doctor-report.json`. Required failures return exit code `1`. With `-Strict`, warnings return exit code `2`.

```powershell
.\scripts\windows\doctor.ps1 -Strict
```

The doctor does not modify the Hakoniwa Core or hakoSim installation.

## Phase W1 Shibuya collision smoke test

The standard installed Core configuration points to `Z:\mmap`. Ensure that directory exists after Windows starts:

```powershell
.\scripts\windows\ensure_hako_mmap.ps1
```

Prepare, start, collide with a known Shibuya building wall, verify `DroneStatus.collided_counts`, and stop:

```powershell
.\scripts\windows\smoke_test.ps1
```

The runtime process is required to load `hakoSim\bin\mujoco.dll` version 3.7.x. Test results are written under `logs/`; the summary is `logs/phase-w1-smoke-result.json`.

For manual operation:

```powershell
.\scripts\windows\prepare_scenario.ps1
.\scripts\windows\start_simulation.ps1
.\scripts\windows\stop_all.ps1
```

Phase W1 uses a workspace-owned mmap directory so it does not clean or overwrite the standard `Z:\mmap` session.

## Phase W4: Windows-native CityGML pipeline

W4 converts a PLATEAU CityGML directory to a separated `buildings.xml`,
integrates it with the workspace-owned drone MJCF, and compiles the result with
Python MuJoCo. It does not invoke bash, WSL, Docker, or a child Python process.

Create or update the isolated Windows venv:

```powershell
.\scripts\windows\setup_city_pipeline.ps1
```

Run the Shibuya conversion from the runtime repository root. Pass absolute
paths because `city_pipeline.py` belongs to the sibling simenv-data repository:

```powershell
$runtimeRepository = (Resolve-Path .).Path
$workspace = Split-Path $runtimeRepository -Parent
& .\runtime\windows\.venv-city\Scripts\python.exe `
  (Join-Path $workspace "hakoniwa-simenv-data\tools\city_pipeline.py") convert `
  --input (Join-Path $workspace "data\plateau\shibuya-2023") `
  --scenario (Join-Path $runtimeRepository "runtime\windows\scenarios\shibuya\city-pipeline.json") `
  --output (Join-Path $runtimeRepository "runtime\windows\generated\shibuya") `
  --base-model (Join-Path $runtimeRepository "runtime\windows\scenarios\shibuya\config\drone\mujoco-shibuya-api-1\drone-reference-w1.xml") `
  --reference-model (Join-Path $runtimeRepository "runtime\windows\scenarios\shibuya\config\drone\mujoco-shibuya-api-1\drone-reference-w1.xml") `
  --collide drone
```

The source CityGML and original scenario MJCF are read-only. Generated files
are written under `runtime\windows\generated\shibuya`:

- `citygml-extracted/`: the same regional CityGML subset to upload as a Mapray Building Dataset
- `buildings-lod1.json`: LOD1 footprint and height extraction
- `buildings-obb.json`: collision boxes and wall segments
- `buildings.xml`: standalone building MJCF
- `drone-base.xml`: original model with prior `body_bldg_*` nodes removed
- `drone.xml`: integrated drone and regenerated buildings
- `manifest.json`: counts, validation result, reference comparison, and SHA-256 hashes

CityGMLの標高は全建物の最小`zmin`を基準に0へ正規化し、その後にscenarioの
`vertical.z_offset`を適用します。参照比較は水平・垂直・3次元のRMS/最大誤差を
`manifest.json`へ記録します。

## Phase W2: Windows WebSocket viewer bridge

W1の共有メモリPDUを pdu_web_bridge.py がv2 WebSocketへ変換する。標準ポートはWebSocket 8765、HTTP 8001（8000は既存Manager.exeと競合）。

    .\scripts\windows\start_simulation.ps1
    .\scripts\windows\start_web_viewer.ps1

viewer URL:
http://127.0.0.1:8001/src/client/index.html

疎通確認は python scripts/windows/smoke_web_viewer.py。停止は stop_web_viewer.ps1 と stop_all.ps1。

## Phase W5: collision events on Mapray

W5ではBridgeがchannel 2 (`ImpulseCollision`)とchannel 18
(`DroneStatus.collided_counts`)を転送します。後者はMuJoCo接触の正式な出力で、
現在のhakoSimでは接触点・法線・強度を直接含まないため、表示側が検出時の位置と
直前の移動ベクトルから推定します。

シミュレーションとビューアーを起動した後、既知の渋谷壁面に対するE2E検証を実行します。

```powershell
.\scripts\windows\start_simulation.ps1
.\scripts\windows\start_web_viewer.ps1
.\scripts\windows\test_phase_w5_collision.ps1
```

結果は`logs/phase-w5-websocket-collision.json`と
`logs/phase-w5-wall-mission.json`へ保存されます。`test_phase_w5_collision.ps1`は、
衝突回数が増加し、期待する`wall`イベントが生成されなければ失敗します。
