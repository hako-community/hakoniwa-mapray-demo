# 渋谷5km四方・広域建物データ選定結果

作成日: 2026-08-13
対象: 渋谷シナリオの5km四方表示
状態: Mapray公開B3Dを実ブラウザで受入確認済み。5km広域coverageは`ready`

## 1. 結論

渋谷5km四方の広域建物は、Mapray公式サンプルが使用する東京23区の公開B3Dから、
必要な第2次地域区画2メッシュだけを読み込む方式を第一候補とする。

- 必要メッシュ: `533935`、`533945`
- 形式: Mapray B3D
- 現行Mapray JS 0.9.6との互換性: 公式0.9.6サンプルと同じ方式
- Mapray Cloudへのアップロード: 不要
- CityGMLの自前B3D変換: 受入確認済みのため不要。障害時フォールバックのみ
- 既存600m詳細資産: Three.js、MuJoCo、非公開B3Dをそのまま保持

Mapray Dataset Catalogは候補として残すが、公開APIからCatalog全体を検索する手段は確認できなかった。
現在のOrganizationに紐づくB3D一覧APIは、Catalog候補の全件一覧ではない。
そのため、Catalog UIで見える候補のID・種別・範囲が分かる場合だけ比較対象へ追加する。

## 2. 5km四方に必要な自治体

国土数値情報の2024年行政区域データと、現在の5km AOIを平面直角座標系で交差計算した。
AOI面積は24.941112km²で、必要な自治体は次の6区である。

| 自治体 | コード | AOI内面積 | AOI比率 |
|---|---:|---:|---:|
| 渋谷区 | 13113 | 11.803108km² | 47.324% |
| 港区 | 13103 | 6.067251km² | 24.326% |
| 目黒区 | 13110 | 4.526677km² | 18.149% |
| 世田谷区 | 13112 | 1.771078km² | 7.101% |
| 新宿区 | 13104 | 0.636103km² | 2.550% |
| 品川区 | 13109 | 0.136895km² | 0.549% |

データ検索へ300mの余裕を付けると、さらに千代田区0.155381km²と中野区0.011846km²が
端部だけ交差する。したがって、表示対象は6区、厳密な300mプリフェッチ対象は8区として扱う。

## 3. 候補比較

| 優先度 | 候補 | 現行Viewer | Cloud登録 | 自前変換 | 判断 |
|---:|---|---|---|---|---|
| 1 | Mapray公開・東京23区B3Dの2メッシュ | 0.9.6で利用可能 | 不要 | 不要 | 実装・ブラウザ受入済み |
| 2 | PLATEAU公式LOD1 3D Tiles | Experimental対応版が必要 | 不要 | 不要 | B3Dに問題がある場合のPoC |
| 3 | PLATEAU CityGMLを自前B3D変換 | 0.9.6で利用可能 | 必要 | 必要 | 最終フォールバック |
| 補足 | Mapray Dataset CatalogのPLATEAU候補 | 種別による | Catalogから組織へ追加する可能性 | 種別による | UI上の候補詳細が得られたら再比較 |

### 第一候補のURL

- `https://opentiles.mapray.com/3dcity/533935/`
- `https://opentiles.mapray.com/3dcity/533945/`

両方の`tile-index.json`についてHTTP 200、B3D format 2、CORS許可を確認した。
東京全域用サンプルの14メッシュを全部読む必要はなく、今回のAOIと300m余裕域にはこの2メッシュで足りる。

### PLATEAU公式3D Tiles

対象8区には、少なくとも最新LOD1テクスチャ付き3D Tilesの安定URLがある。

`https://api.plateauview.mlit.go.jp/datacatalog/3dtiles/{自治体コード}-bldg-lod1-texture-latest/tileset.json`

ただしMaprayでのPLATEAU 3D Tiles表示は、現行0.9.6のB3D経路とは別のExperimental APIである。
第一候補が不十分な場合に、SDK更新を隔離した小規模PoCとして試す。

## 4. 自前変換が必要になった場合の最小量

PLATEAU公式空間検索APIへ5km AOI＋300m余裕域を指定し、最新2025年・仕様5.0の
建築物CityGMLを集計した。8区の自治体アーカイブを丸ごと取得せず、検索で返るGMLだけを取得する。

| 自治体 | GML数 | GML容量 | 建物地物数 |
|---|---:|---:|---:|
| 千代田区 | 2 | 75,675,999 bytes | 2,821 |
| 港区 | 14 | 829,988,786 bytes | 29,281 |
| 新宿区 | 9 | 453,840,789 bytes | 20,071 |
| 品川区 | 2 | 107,121,831 bytes | 4,432 |
| 目黒区 | 12 | 645,102,766 bytes | 38,315 |
| 世田谷区 | 9 | 507,015,644 bytes | 37,879 |
| 渋谷区 | 26 | 1,415,354,873 bytes | 75,855 |
| 中野区 | 3 | 201,225,460 bytes | 15,788 |
| 合計 | 77 | 4,235,326,148 bytes（3.944GiB） | 224,442 |

容量はGML本体だけで、参照テクスチャ容量を含まない。広域背景は標準DEMを継続利用するため、
DEM CityGMLの変換は不要である。さらに削減する場合は、300m余裕域外かつ5km AOIと交差しない
千代田区・中野区を除外でき、その場合は72 GML、約3.687GiBとなる。

## 5. 実ブラウザ確認方法

通常の起動手順でViewerを立ち上げる。既定値が公開広域B3Dになっているため、従来の確認URLを
そのまま開いてよい。明示的に切り替える場合はURLへ次を追加する。

| パラメータ | 用途 |
|---|---|
| `maprayBuildings=public-wide` | 今回の公開B3D 2メッシュ。既定値 |
| `maprayBuildings=private-local` | 従来の600m非公開B3Dとの比較 |
| `maprayBuildings=hybrid` | 両方を重ねる診断用。重複表示の可能性あり |
| `maprayBuildings=none` | 建物なし。地図・DEMとの切り分け |

確認項目は次の通り。

1. 画面のMapray状態にB3Dシーンが2件読み込まれた旨が出る。
2. 開発者ツールのNetworkで`opentiles.mapray.com/3dcity/533935`と`533945`の
   `tile-index.json`および`.bin`がHTTP 200になる。
3. `5km overview`で中央600mの外にも建物が続き、東西南北の端に大きな欠落がない。
4. 建物が地面から大きく浮く、沈む、二重になる等の標高不整合がない。
5. 30機fixture、経路、区域、選択、インシデント操作が従来どおり動く。
6. 初回ロード時間、操作時FPS、ブラウザメモリがPhase E撮影に許容できる。

不具合時は`private-local`または`none`へ切り替えることで、公開B3D由来かViewer全体由来かを
切り分けられる。2026-08-13の受入確認を通過したため、広域coverageを`ready`とし、
自前変換計画はフォールバックとして凍結した。

## 6. ブラウザ受入結果

30機fixtureのデモ自動飛行を有効にし、公開B3D 2メッシュ、Mapray、Three.jsを同時表示して
30秒warmup＋60秒計測を行った。

| 指標 | 結果 | 判定 |
|---|---:|---|
| page FPS median | 44.906 | 合格（30以上） |
| page FPS p5 | 31.630 | 合格 |
| page FPS minimum | 14.976 | カメラ／インシデント切替時の一時低下 |
| frame time p95 | 30.4ms | 合格 |
| Long Task | 4件 | 許容 |
| JS Heap | 182.505→83.505MB | 増加傾向なし |
| uncaught error / rejection | 0 / 0 | 合格 |
| WebGL context lost | 0 | 合格 |

計測中の`store.revision`は423から1009、Mapray軌跡長は41から97へ増加し、最大5件の
インシデントも処理されたため、静止表示ではなく自動飛行時の結果である。

- 画像: `devai/確認8.png`
- JSON: `devai/mapray-operations-benchmark-run-1786605835753.json`

## 7. 実装・台帳

- Viewer設定: `hakoniwa-geo-viewer/config/mapray.json`
- B3D読込処理: `hakoniwa-geo-viewer/src/client/src/mapray_layer.js`
- URL切替: `hakoniwa-geo-viewer/src/client/src/ui.js`
- 機械可読な候補台帳: `runtime/windows/scenarios/shibuya/wide-area-source-catalog.json`
- 広域準備計画: `runtime/windows/scenarios/shibuya/wide-area-5km.json`

## 8. 公式参照先

- [国土数値情報 行政区域データ 2024年](https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N03-2024.html)
- [PLATEAU CityGML空間検索API](https://docs.plateauview.mlit.go.jp/api/rest/operations/datacatalogcitygmlconditions/)
- [PLATEAUデータカタログAPI](https://docs.plateauview.mlit.go.jp/api/rest/operations/datacatalogplateau-datasets/)
- [Mapray JS 0.9.6 東京23区3D建物サンプル](https://mapray.com/documents/mapray-js/examples/0.9.6/objects/display_3d_building_all_tokyo/)
- [Mapray PLATEAU 3D Tilesサンプル](https://mapray.com/documents/mapray-js/examples/current/objects/display_plateau_3dtiles/)
- [Mapray Cloud API Reference](https://resource.mapray.com/doc/cloudapi/index.html)
