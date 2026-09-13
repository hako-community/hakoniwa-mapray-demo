# Mapray × PLATEAU × 箱庭ドローン 統合デジタルツインプラットフォーム

本リポジトリ群は、**Mapray 3D GIS** による広域都市空間・航空管制監視と、**国交省 Project PLATEAU** および **箱庭（Hakoniwa）シミュレータ** によるミクロなドローン機体・物理シミュレーションをリアルタイムに統合・比較するWebデジタルツインプラットフォームです。

---

## 🌟 主な機能と特徴

1. **5km四方 同一条件・上下2画面 比較デモ**:
   - **上段（Mapray 3D GIS）**: 国土地理院/Mapray DEM＋航空写真＋PLATEAU 3D都市モデル（B3D）による広域航空管制（機体位置・対地高度・運航ルート・航跡）を俯瞰。
   - **下段（Direct PLATEAU / Three.js）**: 国交省PLATEAU 3D Tiles（LOD1）＋600m高精度地形＋リアルな3Dドローン機体（姿勢制御・プロペラ回転・物理衝突判定）を詳細追従。
2. **カメラターゲット完全同期**:
   - 「5km全体俯瞰」「600m東京タワー直近」「選択機体追従」を上下の画面でワンクリック同期。
3. **箱庭Core / PDU連携とスタンドアロン両対応**:
   - ブラウザ単体での高精度フリート自動飛行（Synthetic Fleet Fixture）と、箱庭Core＋PDU/WebSocketによる実シミュレーション運航の両方に対応。

---

## 📁 ディレクトリ構成

```text
work_mapray/
├── hakoniwa-mapray-runtime/ # 本リポジトリ（起動・runtime設定・生成状態）
│   ├── runtime/
│   └── scripts/
├── hakoniwa-geo-viewer/     # 統合Webビューア（Mapray + Leaflet + Three.js統合UI）
├── hakoniwa-web3d-drone/    # Three.js 3Dレンダリング・PLATEAU 3D Tiles・機体描画
├── hakoniwa-simenv-data/    # CityGML・DEM・MJCF・3D都市データ生成パイプライン
├── hakoniwa-pdu-bridge-core/# 箱庭PDU / WebSocketブリッジ
└── Plan20260814/            # 比較デモ設計書・計画ドキュメント
```

---

## ⚙️ 環境設定（runtime）

### 1. 必要環境
* **OS**: Windows 10 / 11 (PowerShell 7+ または Windows PowerShell)
* **Python**: 3.9 以上
* **ブラウザ**: WebGL 2.0対応ブラウザ（Chrome または Edge 推奨）
* **Mapray API Key**: [Mapray Cloud](https://cloud.mapray.com/) で取得したAPIキー（無料枠で利用可能）

### 2. `.env` の設定
`runtime/windows/config/.env` を作成し、MaprayのAPI Keyを設定します（※Git管理外ファイルです）。

```dotenv
MAPRAY_API_KEY=your_mapray_api_key_here
```

※Mapray Cloud管理画面の **Allowed Domains** に `localhost:18080` を登録してください（`127.0.0.1` ではなく `localhost`）。

---

## 🚀 スクリプト（scripts）の使い方・デモ起動手順

すべてのスクリプトは **runtimeリポジトリのルート
（`work_mapray\hakoniwa-mapray-runtime`）** から実行します。各スクリプトは
兄弟ディレクトリの `hakoniwa-geo-viewer`、`hakoniwa-simenv-data`、
`hakoniwa-web3d-drone` を共通設定から解決します。

### Mapray 0.9.6 ドローンモデル専用画面

Maprayだけの全画面で、機体1＋独立プロペラ4を表示するデモです。SDKは`0.9.6`に固定し、Three.jsは読み込みません。

```powershell
.\scripts\windows\start_mapray_drone_model_demo.ps1
```

表示URL:

```text
http://localhost:18080/hakoniwa-geo-viewer/src/client/mapray-drone-model.html?droneRender=model
```

終了時は専用停止コマンドを実行します。

```powershell
.\scripts\windows\stop_mapray_drone_model_demo.ps1
```

検証済みDataset IDは`hakoniwa-geo-viewer/config/mapray-drone-model.json`に設定済みです。旧`start_mapray_model_phase0.ps1`とPhase 0 URLは互換入口として残しています。API Keyは従来どおり `runtime/windows/config/.env`だけで管理し、URLやJavaScriptへ埋め込みません。

右上の基準姿勢セレクターで水平、Yaw +90°、Yaw 180°、Roll +10°、Pitch +10°を切り替えられます。`機体を追従`は現在位置を中心にカメラを追従させます。fixtureとPDU入力は同じ`FlightStateStore`→`MaprayDroneModelLayer.updateDroneState()`経路を使用します。

#### Phase 5 性能比較

同じカメラ・ブラウザで`-RenderMode`だけを変えて起動します。`model`は本体1＋プロペラ4、`pin`は比較用Pin 1個、`both`は位置合わせ確認用の同時表示です。

```powershell
.\scripts\windows\start_mapray_drone_model_demo.ps1 -RenderMode model
.\scripts\windows\start_mapray_drone_model_demo.ps1 -RenderMode pin
.\scripts\windows\start_mapray_drone_model_demo.ps1 -RenderMode both
```

ブラウザコンソールの`window.__maprayDroneModelDiagnostics`で次を比較できます。

- `performance.loadDurationMs`: 3D Datasetのロードを含むLayer準備時間
- `performance.averageUpdateMs` / `maxUpdateMs`: 1フレームの機体更新時間
- `browserPerformance.fps`: 直近約1秒のFPS
- `browserPerformance.usedJsHeapBytes`: 対応ブラウザのJavaScript heap使用量
- `cloudDatasetRequestCount`: Cloud Dataset Resourceの要求回数（modelは5、pinは0）
- `browserPerformance.loadWindowResourceCount` / `loadWindowTransferBytes`: Layerロード開始からREADYまでのResource Timing件数と転送量

ブラウザキャッシュの影響を避ける比較では、各モードを別のInPrivateウィンドウで開くか、DevToolsのDisable cacheを有効にします。`transferSize`はブラウザやCDNのResource Timing制約により0になる場合があります。

ChromeによるREADY回帰は、サーバー起動中に次で再実行できます。`model`はMapray CloudのAllowed Domainsとネットワークが必要です。

```powershell
.\scripts\windows\test_mapray_drone_model_browser.ps1 -RenderMode pin
.\scripts\windows\test_mapray_drone_model_browser.ps1 -RenderMode model
.\scripts\windows\test_mapray_drone_model_browser.ps1 -RenderMode both
```

コマンドのJSON出力にはREADY判定に加え、Layerとブラウザの性能値も含まれます。

#### Cloud準備とトラブルシュート

Mapray Cloudでairframeとpropellerの各Datasetが公開・変換完了状態であること、API KeyのAllowed Domainsに`localhost:18080`があることを確認します。Dataset IDは公開識別子なので設定JSONに保持しますが、API Keyや書込トークンは`.env`以外へ入れません。

- `3D Dataset IDが未設定`: `config/mapray-drone-model.json`または起動引数を確認します。
- `HTTP 401/403`: API KeyとAllowed Domainsを確認します。URLへKeyを追加しないでください。
- モデルロードエラーでPinだけ残る: Cloud側の変換状態、Datasetの公開範囲、ネットワークを確認します。
- モデルが重なる／ずれる: `-RenderMode both`でPin中心と機体中心を比較し、右上の既知姿勢を順に確認します。
- ポート18080が別用途で使用中: そのプロセスを確認するか、`-HttpPort`で別ポートを指定します。

Phase 5完了後は必須のPhase 6として、同じvisualを5機以上へ拡張し、機体ごとの生成・破棄、独立姿勢・ローター速度、1/5/10機性能を検証します。

#### Phase 6 複数機モデル

`-FleetSize`は1、5、10を指定できます。標準の`model`では1機あたり本体1＋プロペラ4の`5N` Entityを表示します。

```powershell
.\scripts\windows\start_mapray_drone_model_demo.ps1 -RenderMode model -FleetSize 5
.\scripts\windows\start_mapray_drone_model_demo.ps1 -RenderMode model -FleetSize 10
```

画面右上の機体数セレクターでも1・5・10機を切り替えられます。編隊fixtureは機体ごとに位置、姿勢、4ローター速度を変え、100msごとに`FlightStateStore`を更新します。選択と追従は機体ID単位です。

Fleet診断は`window.__maprayDroneModelDiagnostics`で確認できます。

- `activeDroneCount`: 現在の機体数
- `modelEntityCount` / `expectedModelEntityCount`: 実数と`5N`期待値
- `cloudResourceCreateCount`: 共有Resource生成数。機体数によらずmodelでは2
- `createdDroneCount` / `disposedDroneCount`: 追加・離脱・timeoutのライフサイクル累計
- `layers`: 機体ID別の位置、姿勢、ローター速度・位相

ブラウザ回帰と計測:

```powershell
.\scripts\windows\test_mapray_drone_model_browser.ps1 -RenderMode model -FleetSize 1
.\scripts\windows\test_mapray_drone_model_browser.ps1 -RenderMode model -FleetSize 5
.\scripts\windows\test_mapray_drone_model_browser.ps1 -RenderMode model -FleetSize 10
.\scripts\windows\test_mapray_drone_model_browser.ps1 -RenderMode model -FleetSize 5 -LifecycleTest
```

#### Mapray Cloud用glTFの再生成

Blender 5.2を使い、元のGLBから機体・プロペラの分離型glTF、SHA-256付きmanifest、ライセンスコピーを再生成できます。

```powershell
.\scripts\windows\build_mapray_model_assets.ps1
```

Khronos glTF Validatorを使用する場合は、公式Windows CLIの実行ファイルを指定します。この指定時は、両glTFのValidator errorが0件でなければ処理を失敗させます。

```powershell
.\scripts\windows\build_mapray_model_assets.ps1 `
  -ValidatorPath "<展開先>\gltf_validator.exe"
```

生成先は `runtime/windows/generated/mapray-model-phase0` です。`LICENSE.txt`と検証レポートは生成先ルートへ分離されるため、Cloud登録では`airframe`または`propeller`ディレクトリをそのまま選択できます。

### ① 【推奨】5km四方 東京タワー比較デモ（ワンクリック起動）

MaprayとPLATEAU 3D Tilesを同一の東京タワー5km四方で上下比較する決定版デモです。

```powershell
.\scripts\windows\start_5km_comparison_demo.ps1
```

* **ブラウザURL**:
  ```text
  http://localhost:18080/hakoniwa-geo-viewer/src/client/index.html?scenarioConfig=/hakoniwa-geo-viewer/config/viewer-config-tokyo-tower-5km.json&threejsRoot=/hakoniwa-web3d-drone&scenarioMode=fixture&fleetSize=10
  ```
* **操作方法**:
  1. 起動後、自動的に10機のドローンが東京タワー周辺の空域を自律飛行します。
  2. 左パネルの **`600m Tokyo Tower area`** ボタンを押すと、東京タワー直近（高さ332mの3Dモデルと地形）へズームインします。
  3. **`5km overview (Comparison)`** ボタンを押すと、広域全体俯瞰に戻ります。
  4. ドローンをクリック、または左パネルで選択すると、その機体にカメラがフォーカスします。

---

### ② 箱庭Core＋PDU連携 複数機フリート実運航デモ

箱庭コアの時刻管理・PDU WebSocket通信を経由して複数機を運航するデモです。

```powershell
# 起動 (東京タワー 30機フリート)
.\scripts\windows\start_core_fleet_demo.ps1 -ScenarioName tokyo-tower -FleetSize 30

# 停止
.\scripts\windows\stop_core_fleet_demo.ps1
```

---

### ③ 統合HTTPサーバーの単体起動

静的HTTP配信と `MAPRAY_API_KEY` のセキュア配信（`/__runtime/mapray-config`）を行うサーバーを単体起動します。

```powershell
python scripts\windows\serve_geo_viewer.py `
  --directory . `
  --port 18080 `
  --bind 0.0.0.0 `
  --env-file runtime\windows\config\.env
```

---

### ④ 全プロセスの停止

バックグラウンドで起動しているHTTPサーバーやPDUブリッジを一括終了します。

```powershell
.\scripts\windows\stop_all.ps1
```

---

### ⑤ 動作検証・診断（doctor / test / smoke）

システムの整合性や契約テストを実行します。

```powershell
# 環境・ファイルの健全性チェック
python hakoniwa-geo-viewer/tools/hako.py doctor

# 全単体・結合・契約テストの実行 (74テスト + 11契約テスト)
python hakoniwa-geo-viewer/tools/hako.py test

# HTTP疎通・全アセット取得のスモークテスト
python hakoniwa-geo-viewer/tools/hako.py smoke
```

---

## 📊 デモの見どころ（Mapray vs PLATEAU）

| 比較項目 | 上段: Mapray 3D GIS | 下段: Direct PLATEAU / Three.js |
| :--- | :--- | :--- |
| **主な用途** | **マクロ広域 運航監視・航空管制** | **ミクロ局所 機体挙動・物理シミュレーション** |
| **都市モデル** | Mapray B3D Building Dataset | 国交省 PLATEAU 3D Tiles (LOD1) + 高精度DEM |
| **ドローン表示** | スマートな機体IDピン・対地高度ライン・実飛行軌跡 | リアルな3D機体モデル（姿勢制御・プロペラ回転） |
| **得意領域** | 10km〜広域の都市空間・フリート全体の一括俯瞰 | ビル近接飛行・衝突検知・センサー・ミリ単位の解析 |

---

## 📜 ライセンス

本プロジェクトは Apache-2.0 / MIT ライセンスのもとで公開されています。
詳細は各サブモジュールの `LICENSE` ファイルをご参照ください。
