# Mapray Cloud用ドローンモデル資産

## 対象

- Mapray JS / mapray-ui: `0.9.6`
- 機体入力: `hakoniwa-web3d-drone/assets/models/origin_01_body.glb`
- プロペラ入力: `hakoniwa-web3d-drone/assets/models/propeller_origin_01.glb`
- 出力: `runtime/windows/generated/mapray-model-phase0`

## 再生成

Blender 5.2を既定の場所へインストールした環境では、次を実行する。

```powershell
cd D:\work_mapray\hakoniwa-mapray-demo
.\scripts\windows\build_mapray_model_assets.ps1
```

この処理はBlenderを空シーンで起動し、入力GLBを1つずつ読み込んで`GLTF_SEPARATE`形式へ出力する。アニメーション、カメラ、ライトは出力しない。SHA-256、シーン統計、境界寸法、再インポート結果は`manifest.json`へ保存する。

## Khronos glTF Validator

KhronosGroup/glTF-ValidatorのWindows CLIを展開し、実行ファイルを指定する。

```powershell
.\scripts\windows\build_mapray_model_assets.ps1 `
  -ValidatorPath "<展開先>\gltf_validator.exe"
```

Validatorが1件でもerrorを報告した場合、スクリプトは失敗する。JSONレポートは生成先の`validation`ディレクトリへ保存され、Cloudアップロード対象ディレクトリには入らない。

検証済みバージョン: `2.0.0-dev.3.10`

## 座標・縮尺契約

- 出力glTFはglTF標準の右手座標系、`+Y` Upである。
- 機体正面は`+Z`を基準とする。
- Blender内の境界計測値は、インポートにより変換されたBlender座標（`+Z` Up）で記録される。
- 機体の境界寸法は約`3.5663 x 3.5707 x 0.6339 m`である。
- プロペラの境界寸法は約`2.9600 x 0.3313 x 0.0975 m`である。
- Phase 0表示では機体scaleを`0.6`、プロペラscaleを`0.216`とする。
- ROSオフセットは`+X=前/北、+Y=左/西、+Z=上`として地理座標へ変換する。

プロペラ原点回りの回転方向と取付位置は、`hakoniwa-geo-viewer/config/mapray-model-phase0.json`で管理する。Cloud登録時に4つのプロペラを別々の場所へ置く必要はない。

## Cloudアップロード

機体とプロペラを別々の3D Datasetとして登録する。

### airframe

選択するファイル:

- `origin-01-airframe.gltf`
- `origin-01-airframe.bin`
- `Image_0.png`

Path:

```text
/airframe/origin-01-airframe.gltf
```

### propeller

選択するファイル:

- `origin-01-propeller.gltf`
- `origin-01-propeller.bin`

Path:

```text
/propeller/origin-01-propeller.gltf
```

両方のOrigin:

```text
Longitude: 139.745433
Latitude:  35.658581
Altitude:  180
```

`LICENSE.txt`とValidatorレポートは生成先ルートへ分離されているため、`airframe`または`propeller`ディレクトリをそのままCloudへ指定できる。

## Cloud Dataset

2026-09-12に最初に手動変換・登録した版には、Blenderの既定`Cube`が混入していた。次のDataset IDは接続確認には使えるが、採用モデルとしては使用しない。

```text
airframe:  5121033015132160
propeller: 5198773533802496
```

空シーン初期化を行う本パイプラインで再生成した正式版は、次のDataset IDで登録・検証済みである。

```text
airframe-v2:  5175426158690304
propeller-v2: 5103619808428032
```

Cloud上のglTF、BIN、PNGは、ローカル生成物とSHA-256がすべて一致している。
