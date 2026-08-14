# 5km四方 Mapray vs PLATEAU 比較デモ 実装仕様書

作成日: 2026-08-14  
対象ワークスペース: `D:\work_hako\work_mapray`  
対象エリア: 東京タワー〜渋谷周辺 5km四方  
目的: **既存実装を完全に維持したまま、無料枠（10GB制限）内で「Mapray」と「通常PLATEAU表示」の違いを最も鮮明かつ簡単に体験できる新しいデモを実装・配備する。**

---

## 1. システム構成・アーキテクチャ

本デモは、上下2画面で全く同一の入力条件（地理座標・ドローン運航）を保持しながら、レンダリングおよび配信方式の違いを比較します。

```text
                                  【箱庭 Core / PDU または Fixture】
                                                  │
                                  ドローン位置情報（GPS座標/速度/姿勢）
                                                  │
                        ┌─────────────────────────┴─────────────────────────┐
                        ▼                                                   ▼
         【上段: Mapray 3D GIS】                             【下段: PLATEAU 3D Tiles (Three.js)】
  ・Mapray Cloud / 公開B3Dタイル (533935/533945)      ・PLATEAU公式 3D Tiles API (13103港区ほか)
  ・視界内タイルの動的LODストリーミング配信           ・広域3Dタイル一括/逐次読込・メッシュ描画
  ・地球楕円体＋DEM標高＋航空写真                     ・局所DEM＋3D Tiles
  ・広域ズームでも 60 FPS を維持                      ・広域描画負荷によるフレームレートの差分表示
```

---

## 2. 資産・データ設計（無料枠10GB制限の完全クリア）

| コンポーネント | データソース | 容量・利用枠 |
| :--- | :--- | :--- |
| **上段: Mapray B3D** | Mapray公式公開タイル<br>`https://opentiles.mapray.com/3dcity/533935/`<br>`https://opentiles.mapray.com/3dcity/533945/` | **0 Byte（無料枠を一切消費しない）** |
| **上段: Mapray DEM** | Mapray公式標準標高タイル | 標準無料枠内 |
| **下段: PLATEAU 3D Tiles** | PLATEAU公式 API（港区・渋谷区・千代田区など） | 国交省オープンデータ |
| **ドローン運航** | 5機巡航フリート（東京タワー〜六本木〜麻布台〜愛宕） | 箱庭PDU / Fixture |

---

## 3. 画面UIと操作仕様

### 3.1 画面ラベル
* **上段ラベル**: `[上段] Mapray 3D GIS (クラウド最適化・LODタイル配信)`
  * 説明: `東京5km四方 PLATEAU B3D (533935 / 533945) + DEM標高`
* **下段ラベル**: `[下段] 通常Web表示 (PLATEAU 3D Tiles / 一括描画)`
  * 説明: `PLATEAU公式 3D Tiles API (港区ほか) + Three.js`

### 3.2 カメラ操作・プリセット
1. **`5km Overview`（全体俯瞰）**: 東京タワーを中心とした5km四方全体を見下ろす視点。
2. **`Tokyo Tower Close-up`（東京タワー近景）**: 東京タワー直下および周辺ビル群の近接視点。
3. **`Follow Drone`（ドローン追従）**: 巡航中のドローンを背後から追尾し、ビルの間をすり抜ける迫力ある視点。

---

## 4. 配備ファイル一覧（新規追加・既存非破壊）

1. **設定ファイル**:
   * `hakoniwa-geo-viewer/config/viewer-config-tokyo-tower-5km.json` (新規)
   * `hakoniwa-geo-viewer/config/scenarios/tokyo-tower-5km.json` (新規)
   * `hakoniwa-geo-viewer/config/drone_config-tokyo-tower-5.json` (新規)
2. **起動スクリプト**:
   * `scripts/windows/start_5km_comparison_demo.ps1` (新規)
3. **ドキュメント**:
   * `Plan20260814/5km-comparison-implementation-plan.md` (本書)

---

## 5. 実行手順

### 手順A: ブラウザ単体（Fixtureモード）で今すぐ確認する場合
```powershell
python scripts/windows/serve_geo_viewer.py --directory . --port 18080 --bind 0.0.0.0 --env-file runtime/windows/config/.env
```
ブラウザで以下を開く:
```text
http://localhost:18080/hakoniwa-geo-viewer/src/client/index.html?scenarioConfig=/hakoniwa-geo-viewer/config/viewer-config-tokyo-tower-5km.json&threejsRoot=/hakoniwa-web3d-drone&scenarioMode=fixture&fleetSize=5
```

### 手順B: ワンタッチ起動スクリプトを実行する場合
```powershell
.\scripts\windows\start_5km_comparison_demo.ps1 -Mode fixture -FleetSize 5
```
または箱庭Core実運航モード:
```powershell
.\scripts\windows\start_5km_comparison_demo.ps1 -Mode core -FleetSize 5
```
