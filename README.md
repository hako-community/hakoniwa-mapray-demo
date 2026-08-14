# Hakoniwa Mapray Demo

箱庭（Hakoniwa）のドローンシミュレーション、**Mapray 3D GIS**、および**国交省 Project PLATEAU** を統合し、広域航空管制と局所3D物理挙動をリアルタイムに可視化・比較する Windows 向けデモワークスペースです。

東京タワーおよび渋谷を対象に、**広域 5 km 四方の運航監視（マクロ）** と **600 m 詳細・ドローン機体挙動（ミクロ）** を上下2画面で完全同期して比較・検証できます。

---

## 🌟 主な機能と特徴

1. **5km四方 同一条件・上下2画面 比較デモ**:
   * **上段（Mapray 3D GIS）**: 国土地理院/Mapray DEM＋航空写真＋PLATEAU 3D都市モデル（B3D）による広域航空管制（機体位置・対地高度・運航ルート・航跡）を一括俯瞰。
   * **下段（Direct PLATEAU / Three.js）**: 国交省PLATEAU 3D Tiles（LOD1）＋600m高精度地形＋リアルな3Dドローン機体（姿勢制御・プロペラ回転・物理衝突判定）を詳細追従。
2. **カメラターゲット完全同期**:
   * 「5km全体俯瞰」「600m東京タワー直近（高さ332mの精密3Dモデル）」「選択機体追従」を上下画面でワンクリック同期。
3. **箱庭Core / PDU連携とスタンドアロン両対応**:
   * ブラウザ単体での高精度フリート自動飛行（Synthetic Fleet Fixture）と、箱庭Core＋PDU/WebSocketによる実シミュレーション運航の両方に対応。

---

## 📁 ディレクトリ構成

* `scripts/windows`: 起動・停止・診断・ベンチマーク用の運用スクリプト群
* `runtime/windows/config`: ローカル設定のひな形（`.env.example`、`windows.paths.example.json`）
* `runtime/windows/scenarios`: 渋谷・東京タワーのシナリオ定義
* `runtime/windows/core-fleet`: 箱庭Core フリート PDU 定義
* `docs`: 5 km 比較デモ設計書、データ選定、東京タワー検討資料
* `components.lock.json`: 動作確認済みサブモジュールの Git リビジョン固定ファイル

※生成ログ、mmap、状態ファイル、Mapray API Key などのローカル環境依存ファイルは Git 追跡対象外です。

---

## 🔧 必要なコンポーネント（リポジトリの配置）

本リポジトリの直下に、次の3つのサブモジュールリポジトリをクローンして配置します。

```powershell
git clone https://github.com/hako-community/hakoniwa-geo-viewer.git
git clone https://github.com/hako-community/hakoniwa-web3d-drone.git
git clone https://github.com/hako-community/hakoniwa-simenv-data.git

# components.lock.json に記録された推奨リビジョンへ切り替え
git -C hakoniwa-geo-viewer checkout c378b7f5e6affe1963b6d38d213ed4cebae465f2
git -C hakoniwa-web3d-drone checkout 9084895c1ae5f5dbded50966ddd841b0ff6faaae
git -C hakoniwa-simenv-data checkout b5e4a6e0b5f126ce4ba2912ef4874efbc89132ec

# サブモジュールの依存関係を初期化
git -C hakoniwa-geo-viewer submodule update --init --recursive
git -C hakoniwa-web3d-drone submodule update --init --recursive
```

---

## ⚙️ ローカル環境設定（runtime）

### 1. 必要環境
* **OS**: Windows 10 / 11 (PowerShell 7+ または Windows PowerShell)
* **Python**: 3.9 以上
* **ブラウザ**: WebGL 2.0 対応ブラウザ（Chrome または Edge 推奨）
* **Mapray API Key**: [Mapray Cloud](https://cloud.mapray.com/) で発行したブラウザ用 API キー（無料枠で利用可能）

### 2. 設定ファイルの作成
テンプレートから設定ファイルを作成します。

```powershell
Copy-Item .\runtime\windows\config\windows.paths.example.json `
  .\runtime\windows\config\windows.paths.local.json

Copy-Item .\runtime\windows\config\.env.example `
  .\runtime\windows\config\.env
```

`runtime\windows\config\.env` をテキストエディタで開き、取得した Mapray API Key を設定します。

```dotenv
MAPRAY_API_KEY=your_mapray_api_key_here
```

> [!IMPORTANT]
> Mapray Cloud 管理画面の **Allowed Domains** には、`127.0.0.1` ではなく `localhost:18080` を登録してください。

---

## 🚀 起動スクリプト（scripts）の使い方

すべてのスクリプトは**ワークスペースルート**から実行します。

### ① 【一番おすすめ】東京タワー 5km四方 比較デモ（ワンライナー起動）

Mapray 3D GIS と PLATEAU 3D Tiles を、同一の東京タワー5km四方で上下比較する決定版デモです。

```powershell
.\scripts\windows\start_5km_comparison_demo.ps1
```

* **ブラウザURL**:
  ```text
  http://localhost:18080/hakoniwa-geo-viewer/src/client/index.html?scenarioConfig=/hakoniwa-geo-viewer/config/viewer-config-tokyo-tower-5km.json&threejsRoot=/hakoniwa-web3d-drone&scenarioMode=fixture&fleetSize=10
  ```
* **デモの操作方法**:
  1. 起動後、10機のドローンが東京タワー周辺空域を自動飛行します。
  2. 左パネルの **`600m Tokyo Tower area`** ボタンを押すと、東京タワー直近（高さ332mの精密3Dモデルと地形）へ上下同時にズームインします。
  3. **`5km overview (Comparison)`** ボタンを押すと、5km広域の全体俯瞰に戻ります。
  4. ドローンをクリック、または左パネルで選択すると、その機体にカメラが追従します。

---

### ② 箱庭Core＋PDU連携 複数機フリート実運航デモ

箱庭コアの共有メモリ（mmap）・PDU WebSocket通信を経由して複数機を運航するデモです。

```powershell
# 起動 (東京タワー 30機フリート)
.\scripts\windows\start_core_fleet_demo.ps1 -ScenarioName tokyo-tower -FleetSize 30

# 停止
.\scripts\windows\stop_core_fleet_demo.ps1
```

---

### ③ 渋谷 5km広域シナリオ

渋谷駅周辺の5km広域および600m詳細シナリオを起動します。

```powershell
.\scripts\windows\serve_geo_viewer.py `
  --directory . `
  --port 18080 `
  --bind 0.0.0.0 `
  --env-file runtime\windows\config\.env
```

* **渋谷 5km広域URL**:
  ```text
  http://localhost:18080/hakoniwa-geo-viewer/src/client/index.html?scenarioConfig=/hakoniwa-geo-viewer/config/viewer-config-shibuya.json&threejsRoot=/hakoniwa-web3d-drone&scenarioMode=fixture&fleetSize=30&seed=20260811&maprayBuildings=public-wide
  ```

---

### ④ 全プロセスの停止

バックグラウンドで動作している HTTP サーバーや PDU ブリッジを一括停止します。

```powershell
.\scripts\windows\stop_all.ps1
```

---

### ⑤ 環境診断と動作検証

```powershell
# 環境と依存ファイルの診断
.\scripts\windows\doctor.ps1

# HTTP疎通スモークテスト
.\scripts\windows\smoke_test.ps1

# ビューアおよび Three.js の全単体・契約テスト (74件 + 11件)
python hakoniwa-geo-viewer/tools/hako.py test
```

---

## 📊 デモの見どころ（Mapray vs PLATEAU 比較表）

| 比較項目 | 上段: Mapray 3D GIS | 下段: Direct PLATEAU / Three.js |
| :--- | :--- | :--- |
| **主な用途** | **マクロ広域 運航監視・航空管制** | **ミクロ局所 機体挙動・物理シミュレーション** |
| **都市モデル** | Mapray B3D Building Dataset | 国交省 PLATEAU 3D Tiles (LOD1) + 高精度DEM |
| **ドローン表現** | スマートな機体IDピン・対地高度ライン・実飛行軌跡 | リアルな3D機体モデル（姿勢制御・プロペラ回転） |
| **得意領域** | 10km〜広域の都市空間・フリート全体の一括俯瞰 | ビル近接飛行・衝突検知・センサー・ミリ単位の解析 |

---

## 📜 ライセンス

本プロジェクトは Apache-2.0 / MIT ライセンスのもとで公開されています。
詳細は [`LICENSE`](LICENSE) および各サブモジュールのライセンスファイルをご参照ください。
