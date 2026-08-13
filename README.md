# Hakoniwa Mapray Demo

箱庭のドローンシミュレーションを、Mapray と Three.js で可視化する Windows 向けデモワークスペースです。現時点では渋谷を対象に、600 m 詳細表示と 5 km 四方の広域表示を提供します。

このリポジトリには、起動・停止・診断・ベンチマーク用の `scripts/windows` と、再現に必要な最小限の `runtime/windows` 設定を収録しています。ビューアー、3D 表示、都市データ変換は別の hako-community リポジトリで管理し、固定 revision は [`components.lock.json`](components.lock.json) に記録しています。

## 構成

- `scripts/windows`: Windows ネイティブの運用スクリプト
- `runtime/windows/config`: ローカル設定のひな形
- `runtime/windows/scenarios/shibuya`: MuJoCo と広域データ準備用の渋谷シナリオ
- `runtime/windows/core-fleet`: fleet PDU 定義
- `docs`: 5 km 対応、データ選定、評価、東京タワー追加の検討資料

生成ログ、mmap、状態ファイル、Python 仮想環境、Mapray API key、ローカル絶対パスを含む設定は追跡しません。

## 必要なコンポーネント

このリポジトリ直下に次の3リポジトリを配置してください。

```powershell
git clone https://github.com/hako-community/hakoniwa-geo-viewer.git
git clone https://github.com/hako-community/hakoniwa-web3d-drone.git
git clone https://github.com/hako-community/hakoniwa-simenv-data.git

git -C hakoniwa-geo-viewer checkout 44790101e4a261c3afb45b369c1660d379253245
git -C hakoniwa-web3d-drone checkout d6a2f91f7919a03879488bf7521eda0c8a0dfdbc
git -C hakoniwa-simenv-data checkout b7282c8e97ba2bbab5cd4b93c43d583fe62b5730

git -C hakoniwa-geo-viewer submodule update --init --recursive
git -C hakoniwa-web3d-drone submodule update --init --recursive
```

上記 commit は現在 Draft PR として公開中です。確定 revision は `components.lock.json` を更新して管理します。

## ローカル設定

標準インストール先以外を使う場合は、例をコピーしてローカルファイルだけを編集します。

```powershell
Copy-Item .\runtime\windows\config\windows.paths.example.json `
  .\runtime\windows\config\windows.paths.local.json
Copy-Item .\runtime\windows\config\.env.example `
  .\runtime\windows\config\.env
```

`.env` の `MAPRAY_API_KEY` には Mapray Cloud で発行したブラウザ API key を設定してください。`.env` と `*.local.json` は Git の対象外です。

## 確認と起動

```powershell
.\scripts\windows\doctor.ps1
.\scripts\windows\start_simulation.ps1
.\scripts\windows\start_web_viewer.ps1 -HttpPort 18080
```

5 km 四方の渋谷デモは、HTTP サーバーをポート `18080` で起動した場合、次の URL で確認できます。

```text
http://localhost:18080/hakoniwa-geo-viewer/src/client/index.html?scenarioConfig=/hakoniwa-geo-viewer/config/viewer-config-shibuya.json&threejsRoot=/hakoniwa-web3d-drone&scenarioMode=fixture&fleetSize=30&seed=20260811&maprayBuildings=public-wide
```

停止は次を使います。

```powershell
.\scripts\windows\stop_web_viewer.ps1
.\scripts\windows\stop_all.ps1
```

詳細は [`runtime/windows/README.md`](runtime/windows/README.md) を参照してください。

## ライセンスと由来

このデモのライセンスは [`LICENSE`](LICENSE) を参照してください。各コンポーネント、PLATEAU、Mapray SDK、機体モデルなどの第三者成果物には、それぞれのライセンスと利用条件が適用されます。
