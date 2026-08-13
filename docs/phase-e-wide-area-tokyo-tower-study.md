# Phase E着手前の広域表示・東京タワーシナリオ検討

作成日: 2026-08-13
対象: `work_mapray` / Mapray広域運航管理デモ
状態: 方針検討。Cloudへの新規アップロード、既存Datasetの更新・削除は未実施

## 1. 結論

現状は「5km表示がまったくない」のではなく、次の二層構成である。

- 約5km四方の運航境界、経路、区域、機体、軌跡、インシデント: 実装済み
- 5km俯瞰カメラとMapray標準地図／標準DEM: 実装済み
- 詳細なPLATEAU Building Dataset、独自DEM、Three.js／MuJoCo環境: 原点周辺600m四方のみ
- 5km全域の詳細3D都市B3D: 未整備

Phase Eの動画・スクリーンショットを確定する前に、短い「Stage 2準備」を挟む。
また、対象地域は渋谷から東京タワー周辺へ変更できる。ただし渋谷を上書きせず、
`shibuya`と`tokyo-tower`を切り替え可能な独立シナリオとして追加する。

推奨構成は次のハイブリッド方式である。

1. Mapray広域背景は、Mapray公式の東京23区公開B3DからAOIに必要な2メッシュだけを優先して試す。
2. Dataset Catalog候補またはPLATEAU公式3D Tilesは、公開B3Dの受入条件を満たさない場合に比較・技術検証する。
3. Catalogの有無に関係なく、東京タワー周辺600mのThree.js／MuJoCo物理環境は港区PLATEAU CityGMLから生成する。
4. 5km全域を単一GLBまたは単一MuJoCoモデルへ投入しない。

## 2. 現状確認

### 2.1 現在の「5km」の意味

`shibuya-wide-area-5km.geojson`の運航境界は、おおむね東西4.75km、南北5.12kmの矩形である。
これは「半径5km」ではない。半径5kmを要求する場合は直径10km、面積約78.5km2となり、
必要な自治体数、データ量、カメラ条件が大きく変わる。

本書では、現行と同じ「約5km四方」を前提とする。

### 2.2 現在の600m制約

`runtime/windows/scenarios/shibuya/city-pipeline.json`は次の設定である。

- `north_south_half_m = 300`
- `east_west_half_m = 300`
- 地形格子 `257 x 257`

この範囲から次を生成している。

- `buildings-lod1.json`: Three.js用LOD1都市
- `buildings-obb.json` / `buildings.xml`: MuJoCo用衝突形状
- `terrain-grid.json`: Three.js用地形
- `terrain.hfield`: MuJoCo用地形
- `terrain-mapray.tif`: Mapray Cloud DEM入力
- `citygml-extracted`: Mapray Building Dataset入力

600m範囲だけで、LOD1建物801棟、建物衝突geom 4,266件となっている。
したがって、5km全域を同じ密度でMuJoCoへ固定ロードする構成は採用しない。

### 2.3 5km俯瞰の確認方法

プレゼン確認URLに`localPresentation=1`が付いている場合、開始時表示とfixture飛行を
意図的に600m範囲へ寄せる。5km確認時はこのパラメータを外す。

`5km overview`は、運航GeoJSON全体へLeafletをfitし、Maprayカメラを約6.5km高度へ移動する。

切り分けは次のとおり。

| 表示結果 | 判定 |
|---|---|
| 経路・区域・機体は5kmに広がるが、詳細建物は中央600mだけ | 現行仕様どおり |
| 地図・地形も表示されない | Mapray認証、初期化、DEM providerを確認 |
| 機体も600mに固まる | `localPresentation=1`またはfixtureモードを確認 |
| Three.jsの遠方が空白 | カメラfar値ではなく、元資産が600mしかないため |

## 3. 広域データの推奨レイヤー構成

| レイヤー | 対象範囲 | 推奨データ／方式 | 主な用途 |
|---|---:|---|---|
| 地図・地球地形 | 5km～都市全域 | Mapray標準地図＋標準DEM | 広域状況把握 |
| 広域建物 | 5km以上 | LOD1 B3DまたはPLATEAU 3D Tiles | 都市形状、見通し、位置関係 |
| 重点地区建物 | 600m～1km | テクスチャ付きLOD2/LOD3 | ランドマーク、事故地点 |
| 物理建物 | 機体周辺または航路回廊 | LOD1/OBB衝突プロキシ | MuJoCo衝突判定 |
| 物理地形 | 600m～1km区画 | 高解像度HField | 対地高度、地表衝突 |
| 運航情報 | 5km～数十km | GeoJSON、将来はMVT | 経路、区域、拠点、警告 |

広域表示と局所物理を同じ表示範囲にする必要はない。ただし、原点、緯度経度、標高基準、
建物ID、シナリオIDの契約は共通にする。

## 4. 広域データ準備手順

### 4.1 AOIを先に固定する

運航対象範囲をGeoJSON Polygonで定義し、表示、CityGML検索、データ抽出、coverage検証の
単一入力とする。現行約5km四方に200～300mのデータ余白を加える。

物理用`extent ±300m`と広域表示AOIは別設定にする。

### 4.2 PLATEAU原本をAOI交差で選ぶ

手元の渋谷区2023データは、区内15.11km2、LOD1建物41,626棟を収録している。
一方、現行5km運航矩形は約25km2で渋谷区外へ跨るため、渋谷区原本だけでは全域を覆えない。

対象自治体を名称で固定せず、AOIと自治体／地域メッシュの交差で決定する。
渋谷中心の場合は、新宿区、港区、目黒区、世田谷区、余白によっては中野区が候補となる。

PLATEAU公式データカタログAPIから、次を取得できる。

- 自治体単位の最新CityGML URL
- 建物LOD別の3D Tiles URL
- テクスチャ有無
- MVT、地形等の配信情報

### 4.3 空間分割を先に行う

広域CityGMLは次の順で処理する。

1. AOIと交差する地域メッシュだけを選択する。
2. 1km程度の空間区画またはPLATEAU地域メッシュ単位に分割する。
3. 各区画の建物数、LOD、テクスチャ参照、容量を計測する。
4. Mapray Building Dataset入力は、GMLとAppearance参照を維持した自己完結チャンクにする。
5. 各チャンクを「GML 1件＋参照テクスチャ999件以下」にする。

現在の600m詳細地区でも、CityGML 1件とテクスチャ2,634件、合計約135MBとなり、
3つのBuilding Datasetへ分割した。5km全域をすべてテクスチャ付きで登録する方式は
Dataset数と運用負荷が急増するため、次の優先度とする。

- 広域: LOD1、非テクスチャまたは簡略材質
- 東京タワー、事故地点、拠点周辺: テクスチャ付きLOD2/LOD3
- Three.js／MuJoCo: 現在地周辺の局所区画のみ

### 4.4 DEMを表示用と物理用に分ける

現在の600m・257x257格子と同じ密度を5km全域へ単純拡大しない。

- Mapray表示: 標準DEM、または広域用の低～中解像度GeoTIFF
- Three.js／MuJoCo: 600m～1km区画の高解像度格子
- 長距離運航: 必要区画だけを切り替えるか、航路回廊を生成

Mapray Cloud用DEM GeoTIFFは、公式条件に従いEPSG:4326、Float32、標高基準、nodata、
RasterTypeを検証する。

### 4.5 Cloud投入前に台帳化する

Cloudへ変更を加える前に、次のdry-run成果物を生成する。

- `aoi.geojson`
- `source-manifest.json`: 自治体、年度、配信URL、ライセンス、checksum
- `coverage.geojson`: 建物／地形／詳細地区の実coverage
- `build-plan.json`: チャンク数、ファイル数、容量、予定Dataset数
- `dataset-registry.json`: Dataset ID、名称、種別、所有者、公開範囲、attribution
- 更新・ロールバック・削除手順

## 5. 東京タワー周辺への変更

### 5.1 実現可能性

実現可能である。東京タワー所在地は東京都港区芝公園4丁目2番8号で、ランドマーク自体は
高さ333mである。シナリオ原点候補はおおむね次とする。

- latitude: `35.6586`前後
- longitude: `139.7454`前後
- horizontal CRS: `EPSG:6677`を継続
- frame: `mujoco_x_north_y_minus_east_z_up`を継続

最終原点は、PLATEAU上の東京タワー形状、地形、運航経路を確認して数十m単位で調整する。

### 5.2 港区PLATEAUの提供状況

2026-08-13にPLATEAU公式データカタログAPIを確認した結果、港区（自治体コード`13103`）には
次の最新エンドポイントがある。

| 種別 | 提供状況 | 安定URL |
|---|---|---|
| 建物LOD1・テクスチャあり | あり | `https://api.plateauview.mlit.go.jp/datacatalog/3dtiles/13103-bldg-lod1-texture-latest/tileset.json` |
| 建物LOD2・テクスチャなし | あり | `https://api.plateauview.mlit.go.jp/datacatalog/3dtiles/13103-bldg-lod2-notexture-latest/tileset.json` |
| 建物LOD2・テクスチャあり | あり | `https://api.plateauview.mlit.go.jp/datacatalog/3dtiles/13103-bldg-lod2-texture-latest/tileset.json` |
| 建物LOD3・テクスチャなし | あり | `https://api.plateauview.mlit.go.jp/datacatalog/3dtiles/13103-bldg-lod3-notexture-latest/tileset.json` |
| 建物LOD3・テクスチャあり | あり | `https://api.plateauview.mlit.go.jp/datacatalog/3dtiles/13103-bldg-lod3-texture-latest/tileset.json` |
| 最新CityGML | あり | `https://api.plateauview.mlit.go.jp/datacatalog/citygml/13103-latest/citygml.zip` |

ただし、東京タワー本体がどの地物型、LOD、テクスチャ品質で収録されているかは、
PLATEAU VIEWまたは3D Tiles実表示で確認してから採用を確定する。

### 5.3 変更対象

渋谷設定を直接書き換えず、次の東京タワー用資産を追加する。

| 現行 | 東京タワー用追加案 |
|---|---|
| `config/scenarios/shibuya.json` | `config/scenarios/tokyo-tower.json` |
| `config/geo-origin.json` | `config/geo-origin-tokyo-tower.json` |
| `config/mapray.json` | `config/mapray-tokyo-tower.json` |
| `operations/shibuya-wide-area-5km.geojson` | `operations/tokyo-tower-wide-area-5km.geojson` |
| `web3d-scene-shibuya.json` | `web3d-scene-tokyo-tower.json` |
| `runtime-assets/shibuya/` | `runtime-assets/tokyo-tower/` |
| `runtime/windows/scenarios/shibuya/` | `runtime/windows/scenarios/tokyo-tower/` |
| `runtime/windows/generated/shibuya/` | `runtime/windows/generated/tokyo-tower/` |

東京タワー中心の約5km四方は港区だけでなく、AOIと余白に応じて千代田区、中央区、
渋谷区、品川区、新宿区等へ跨る可能性がある。広域建物は自治体コードを固定列挙せず、
AOI交差によって必要な自治体と3D Tilesを選ぶ。

### 5.4 作業量の違い

| 変更範囲 | 内容 | 難度 |
|---|---|---:|
| Mapray背景とカメラだけ東京タワーへ移動 | 原点、カメラ、運航GeoJSON、広域建物を変更 | 小～中 |
| Three.js局所表示も移動 | 港区CityGMLから600m地形・LOD1建物を再生成 | 中 |
| MuJoCo衝突まで移動 | OBB、MJCF、HField、初期位置、衝突fixtureを再生成 | 中～大 |
| 5km全域を物理化 | 動的区画ロードまたは航路回廊が必要 | 大。初期デモでは非推奨 |

## 6. Mapray Dataset Catalogの利用可否

### 6.1 結論

利用可能な候補がBuilding/B3Dで、現在のAPI KeyまたはAccess Tokenから参照可能であれば、
現行実装へDataset IDを設定して背景都市として利用できる可能性が高い。

ただし、Catalogに「PLATEAU」と表示されているだけでは採用を確定できない。
次を個別に確認する。

- Dataset種別: Building/B3D、3D Dataset、3D Tiles、DEM、Point Cloudのどれか
- 対象範囲: 東京タワー周辺と5km AOIを覆うか
- LODとテクスチャ
- Dataset IDまたは配信URL
- 使用するAPI Key／Access Tokenから取得可能か
- attribution、利用条件、商用デモでの表示可否
- 更新時に内容やURLが変わるか

### 6.2 現行アダプターでそのまま使えるもの

現行`mapray_layer.js`は、`buildingDatasetIds`ごとに
`GET /b3ddatasets/v2/{id}`を呼び、返されたB3D URLを`StandardB3dProvider`へ渡す。

したがって、Catalog候補がBuilding/B3Dなら、まず次だけで試験できる。

1. CatalogでDataset ID、coverage、attributionを確認する。
2. 現在の認証情報から`GET /b3ddatasets/v2/{id}`が成功するか確認する。
3. 東京タワー専用`mapray-tokyo-tower.json`の`buildingDatasetIds`へ設定する。
4. B3D表示、カメラ、FPS、転送量を確認する。

通常の3D Dataset、Point Cloud、DEM、Vector Tileの場合は、それぞれ別のprovider／loaderが必要であり、
`buildingDatasetIds`へ入れるだけでは表示できない。

### 6.3 現在のOrganizationから確認できたDataset

2026-08-13にOrganization TokenでB3D一覧を読み取り確認した結果、現在のOrganizationから
列挙できたのは次の4件だけだった。

- `shibuya-textured-2023-001`
- `shibuya-textured-2023-002`
- `shibuya-textured-2023-003`
- `shibuya`

いずれも`ready`だが、`is_catalog=false`、`is_public=false`である。
これは「Mapray Cloud UIのDataset Catalogに他の候補が存在しない」という意味ではない。
公式のB3D一覧APIは、認証情報に紐づくOrganizationのDataset一覧を返す仕様であり、Catalog全体を
検索するAPIとしては公開されていないためである。

また、`runtime/windows/config/.env`の既存`MAPRAY_API_KEY`は、APIへの直接照会では
`invalid api key`となった。Organization Tokenでは上記4件を正常取得できた。
デモ用API Keyは再発行または有効性確認が必要である。

### 6.4 Catalog候補がPLATEAU 3D Tilesの場合

現行プロジェクトはMapray JS CDN版0.9.6とB3D providerを使用しており、
PLATEAU 3D Tilesの直接表示は実装していない。

一方、Mapray公式には、`Standard3DTileProvider`と
`b3d_collection.createMapray3DTileScene()`を使ってPLATEAU 3D Tilesを表示するサンプルがある。
このサンプルは3D Tiles用の対応ビルドとAccess Tokenを使用し、Experimental Featureと明記されている。

したがって、3D Tiles案は有力だが、現行0.9.6設定へURLを追加するだけでは動かない。
別の`mapray-3dtiles`アダプターとして小さな技術検証を行い、既存B3D版を壊さず比較する。

## 7. 選択肢比較

| 案 | 広域表示 | 局所物理 | 利点 | 注意点 |
|---|---|---|---|---|
| A. Mapray公式の東京23区公開B3D | 可能 | 不可 | 現行0.9.6互換、Cloud登録・自前変換不要 | 実ブラウザで品質・性能の受入確認が必要 |
| B. Catalog Building/B3Dを利用 | 可能 | 不可 | 現行0.9.6へ最小変更、再アップロード不要 | coverage、認証、利用条件に依存 |
| C. PLATEAU公式3D TilesをMaprayで直接利用 | 可能 | 不可 | 最新URL、広域タイル配信、Cloud再変換不要 | Mapray 3D Tiles対応版への移行、Experimental API |
| D. CityGMLを自前B3D化 | 可能 | CityGMLから生成可能 | 現行パイプラインと整合、範囲を管理できる | Cloud容量、変換、Dataset分割、運用台帳が必要 |

推奨は、Aを広域表示、既存または新規CityGML由来資産を局所物理へ使うハイブリッドである。
Aが受入条件を満たさない場合だけ、B、C、Dの順に進む。

## 8. Phase E前の推奨実施順序

### E0-1: 既存5km表示の再確認

1. `localPresentation=1`なしで起動する。
2. `5km overview`で経路、区域、機体、地図、標準DEMを確認する。
3. 公開B3D指定時は中央600mの外にも広域建物が続くことを確認する。
4. Mapray失敗時のLeafletフォールバックを確認する。

### E0-2: Catalog候補の判定

1. Mapray Cloud UIで東京タワー／港区／PLATEAUの候補を開く。
2. Dataset名、種別、ID、coverage、LOD、attributionを記録する。
3. Building/B3Dなら現行アダプターで読み取り試験する。
4. 3D Tilesなら、公式PLATEAU港区URLを使う別アダプターPoCへ進む。

### E0-3: Mapray-only東京タワー最小シナリオ

1. 東京タワー原点とカメラを設定する。
2. 5km運航境界、3航路、拠点、進入禁止区域、事故地点を作る。
3. 30機fixtureを表示する。
4. 初回表示時間、転送量、FPS、LOD切替を記録する。

### E0-4: 600m局所物理の移植

1. 港区最新CityGMLを取得する。
2. 東京タワー周辺600mを抽出する。
3. LOD1、OBB、MJCF、地形格子、HFieldを生成する。
4. 東京タワー形状が衝突対象として適切か確認する。
5. Mapray、Three.js、MuJoCoで原点・標高・建物位置を比較する。

### E0-5: Phase E成果物確定

1. 5～7分台本の対象シナリオを確定する。
2. coverageとデータ由来を画面に表示する。
3. Mapray、Leafletフォールバック双方の動画とスクリーンショットを更新する。
4. Catalog利用条件とattributionを成果物へ反映する。

## 9. 合格条件

- 5km全景から東京タワー／インシデント地点へ3操作以内で到達できる。
- 広域建物のcoverage外を誤って詳細都市として説明しない。
- 東京タワーの位置、地形、周辺建物に目視できる大きなずれがない。
- Mapray全体表示でページFPS中央値30以上を維持する。
- 初回転送量とキャッシュ後転送量を実測する。
- MaprayとThree.js／MuJoCoで機体ID、インシデントID、座標が一致する。
- CatalogまたはPLATEAUのattributionと利用条件を画面・資料へ表示する。
- Mapray利用不能時もLeaflet＋Three.js局所表示でデモを継続できる。
- 渋谷シナリオの既存回帰テストを維持する。

## 10. 直近の判断事項

実装前に次を確定する。

1. 「5km」は約5km四方か、半径5kmか。
2. 東京タワーはMapray背景だけの変更か、Three.js／MuJoCo物理まで移植するか。
3. Mapray Dataset Catalog候補のDataset名、種別、ID、coverage、利用条件。
4. Mapray 0.9.6を維持するか、3D Tiles対応版を並列検証するか。
5. 本番デモをfixture、箱庭コアkinematic、MuJoCo liveのどれにするか。

本書の推奨初期値は、「約5km四方」「東京タワー周辺600mのみ物理化」
「広域はMapray公式の東京23区公開B3Dを第一候補」「不十分ならCatalog B3D、PLATEAU 3D Tilesを順に検証」
「渋谷と東京タワーを並列保持」である。

## 11. 2026-08-13 渋谷対応の開始結果

利用者との合意により、AOIは「5km四方」、実装順は「渋谷、東京タワー、地点選択」とした。
東京タワーは、後続検討で渋谷と同等機能にする。

今回、Cloudを変更しない範囲で次を実装した。

- 運航境界を中心 `(139.70375, 35.659)` の実測 `5000.0m x 5000.0m`へ補正。
- 既存600mのLOD1、textured B3D、MuJoCo資産は変更せず維持。
- 渋谷Scenarioへ、5km広域は`source-preparation`、600m局所は`ready`というcoverage契約を追加。
- Viewerのcoverage表示と局所内外判定をScenario設定から取得するよう変更。
- PLATEAU原本を破壊せず調査する`wide-area-plan`コマンドを追加。
- 渋谷用設定とdry-run結果を
  `runtime/windows/scenarios/shibuya/wide-area-5km.json`、
  `runtime/windows/generated/shibuya/wide-area-plan.json`へ保存。

dry-run結果は次の通り。

| 項目 | 結果 |
|---|---:|
| AOI | 5000.0m x 5000.0m |
| データ検索buffer | 300m |
| 選択GML | 28（bldg 26、dem 2） |
| GML＋関連texture等 | 17,964ファイル、2,471,783,199 bytes（約2.30 GiB） |
| Mapray Dataset数の下限 | 18（CityGML分割前のファイル数だけによる下限） |
| Mapray upload readiness | `false` |

未readyの理由は、5km四方が渋谷区外へ広がる一方、現在ローカルにあるPLATEAU原本が
渋谷区2023年度版だけだからである。また実アップロード前には、texture参照を維持する分割で
Dataset数を再計算する必要がある。Mapray CloudへのDataset作成・アップロードは今回実施していない。

この記述はローカルの渋谷区原本だけを前提にした初期dry-runである。後続調査により、
広域表示についてはCloudアップロードを伴わない公開B3D候補を選定した。

## 12. 2026-08-13 隣接自治体・配信候補の確定結果

- 5km AOIが交差する自治体は、渋谷、港、目黒、世田谷、新宿、品川の6区。
- 300m余裕域は、上記に千代田、中野の端部を加えた8区。
- Mapray公式の東京23区B3Dのうち、必要メッシュは`533935`、`533945`の2件だけ。
- 現行Mapray JS 0.9.6へ公開B3D読込を実装し、既定値を`public-wide`とした。
- この候補はブラウザ受入確認を通過し、5km表示用のCityGML自前変換は不要となった。
- 最終フォールバックのCityGML量は、300m余裕域込みで77 GML、約3.944GiB。DEM変換は不要。
- 30機デモ自動飛行でFPS中央値44.906、p5 31.630、エラー0、WebGL喪失0を確認し、
  5km広域coverageを`ready`へ確定した。

詳細、区別の面積・容量、比較URL、ブラウザ確認手順は
[`shibuya-5km-wide-area-data-selection.md`](./shibuya-5km-wide-area-data-selection.md)を参照する。

## 13. 2026-08-13 下段Three.js 5km簡略表示の実装

渋谷シナリオへ、PLATEAU公式LOD1 3D Tilesを必要な視錐台だけ読むストリーミング表示を追加した。
対象は5km AOIと交差する港区、新宿区、品川区、目黒区、世田谷区、渋谷区の6区である。
各URLは`bldg-lod1-texture-latest`の安定したCatalog別名を設定し、2026-08-13にルート
`tileset.json`がすべてHTTP 200で取得できることを確認した。ローカルへCityGMLや全区GLBを追加せず、
画面解像度・カメラ距離に応じたタイルだけを取得するため、自前変換範囲は0件のままである。

表示は二つのscopeを排他的に切り替える。

- `wide`: 5km PLATEAU DEM、公式PLATEAU LOD1 3D Tiles。SSEの`errorTarget=24`で街区タイルまで細分化し、タイル境界球で5km AOI外を読込対象から除外する。
- `local`: 既存600m地形、801棟のローカルLOD1、MuJoCo物理資産。従来の座標・標高契約を維持する。

公式LOD1のB3DM内GLBは`KHR_draco_mesh_compression`を必須とするため、Three.js 0.160固定版の
`DRACOLoader`を登録し、同じ固定版のWASMデコーダーを2 workerで利用する。
B3DM内GLBの実頂点位置は`CESIUM_RTC.center`によりECEF座標へ復元されるため、Draco用の
カスタム`GLTFLoader`には`GLTFCesiumRTCExtension`も明示的に登録する。これを省略すると
タイルの境界球は可視でも建物メッシュだけがローカル原点から外れ、地面のみが表示される。

自治体全体を覆う粗い親タイルは5km AOI内外の建物を一つのB3DMに含むため、境界球による
読込判定だけではAOI外の実メッシュを除外できない。このため運航境界中心
`(139.70375, 35.659)`へ5km地面を合わせ、4枚のThree.js clipping planeで建物を厳密に
5km四方へ切り取る。同時downloadは自治体ごとに2件へ制限する。

2026-08-13の実タイル解析では、渋谷区tilesetは深さ0～3の幾何誤差が概ね100～300で、
これらの親B3DMは全建物の簡略形状ではなく高層・代表建物だけを含んでいた。深さ4の
`geometricError=0`で初めて連続した街区となる。`errorTarget=96`では親LODで停止して街が
疎らになるため、5km俯瞰でも`24`まで細分化する。LOD1無テクスチャ版のCatalog別名は
contentを持たない空tilesetを返したため、表示元には採用しない。

通常の3D Tiles traversalは表示カメラの視錐台だけを要求するため、初期視点の外側は時間を
待ってもロードされず、マウスで向けた時点で初めて現れる。5km overviewではこの挙動を避けるため、
表示には使わない1600px相当の正射影プリロードカメラを5km AOI上空7000mへ置き、6ソースへ
追加登録する。表示カメラもAOI中心を向く高度7600mの俯瞰へ変更する。全AOIの街区をactiveに
できるよう、LRUはソースごとに最大320・縮退先240タイルとする。プリロードカメラはレンダリング
対象ではなく、3D Tilesの要求範囲とSSE計算だけに使う。

確認15では建物表示が5kmの大部分まで広がった。公園、神社境内、道路、鉄道など建物のない領域は
意図した空白である。一方、街区形状に沿わない矩形の空白はキャッシュ縮退による欠落の可能性がある。
次回の判定用に、自治体ごとのcached／active／visible／downloading／parsing／failed数を
`sourceStats`として診断へ追加した。キャッシュ上限も上記320／240へ拡大している。

### 13.1 5km DEMと建物標高の整合

従来の広域地面は標高15.07mの平面だったため、谷地・台地の実標高を持つ3D Tiles建物との間に
隙間が生じた。これを解消するため、ローカルに取得済みのPLATEAU CityGML TINRelief
`533935_dem_6697_op.gml`と`533945_dem_6697_op.gml`から、5km四方の表示用DEMを生成した。

- 中心: 緯度35.659、経度139.70375
- 範囲: 東西・南北とも±2500m
- 格子: 513×513、約9.77m間隔
- 絶対標高: 0.571～43.386m
- 配信用資産: `hakoniwa-geo-viewer/runtime-assets/shibuya/terrain-grid-wide-5km.json`
- 再生成設定: `runtime/windows/scenarios/shibuya/wide-area-terrain.json`
- 生成結果: `runtime/windows/generated/shibuya-wide-5km/terrain-manifest.json`

格子内の`modelHeightsM`は基準高15.07mを差し引いた箱庭座標である。広域AOI中心は既存の箱庭原点
から北へ-388.000m、東へ-226.855mにあるため、DEMをROS座標`[-388.000, 226.855, 0.0]`へ置く。

確認17で約37mの浮きが残った原因は、公開3D TilesがWGS84楕円体高、CityGML DEMが東京湾平均海面
基準の標高であることだった。国土地理院「日本のジオイド2011（Ver.2.2）」による箱庭原点
`(35.6625, 139.70625)`のジオイド高は36.7782mである。したがって、3D TilesのECEFローカル原点を
`15.07 + 36.7782 = 51.8482m`の楕円体高へ置き、建物を`標高 - 15.07m`の箱庭座標へ変換する。
AOI中心のクリップ基準には同地点の`15.07 + 36.7677 = 51.8377m`を使う。5km内のジオイド高変化は
原点との差だけが残るが、建物の浮きとして見える約37mの一定誤差は除去される。従来の600m DEM、
801棟LOD1、MuJoCo物理資産は変更しない。

確認18の後、渋谷原点を含む公開2025年B3DMを実際にDraco展開し、215棟の頂点をglTF Y-upから
3D Tiles Z-upへ変換してECEFへ復元した。建物底面と3D Tilesメタデータの`_zmin - 15.07m`は
RMS 0.012mで一致し、51.8482mの原点補正自体が正しいことを確認した。一方、2025年建物底面と
2023年DEM格子の差は中央値-0.343m、RMS 0.851m、最小-4.975mだった。年度差と約9.77m格子で
斜面を平滑化した影響を吸収するため、広域建物だけを0.5m上げる表示クリアランスを設定する。

また、確認18はOrbitControlsが広域DEM下面へ回り込んだ視点を含んでいた。`wide`ではpanを無効、
極角を1～88度、最短距離を100mとして、カメラが地形下面へ入らないようにする。`local`へ戻すと
panと従来に近い1～179度の操作範囲を復元する。

確認19で、5km広域のDEM・建物表示と地下回り込み防止、および600m詳細へ戻した際の従来操作範囲
の復帰を受入確認した。広域建物とDEMの局所的な最大数mの年度差・格子補間差は、今回の簡略表示の
本質的要件ではないため、0.5m表示クリアランスを最終値とする。

### 13.2 最終ブラウザ性能確認

`devai/mapray-operations-benchmark-run-1786619350172.json`で、30機fixture・デモ自動飛行・
30秒warmup＋60秒計測を実施した。結果は次のとおりである。

| 項目 | 結果 | 判定 |
|---|---:|---|
| page FPS median | 22.371 | 目標30 FPS未達 |
| page FPS p5 | 21.259 | 最低基準20 FPS以上 |
| frame time p95 / p99 | 48.5 / 48.7 ms | 広域表示負荷あり |
| Long Task | 2件、合計213 ms、最大116 ms | 前回より改善 |
| JS Heap | 1475.874 → 1855.078 MB | 60秒では未収束、長時間確認が必要 |
| error / rejection / WebGL loss | 0 / 0 / 0 | 合格 |

自治体6ソースはすべてreadyで、計測終了時のdownload／parse／failedは全ソース0だった。キャッシュは
合計478タイル、active 337、visible 266で安定し、表示欠落を示す失敗はない。自動シナリオで600m
局所表示中は約55 FPSだったが、5km広域へ戻ると約20～23 FPSとなったため、主な描画負荷は下段の
広域PLATEAU建物である。したがって、5km DEM・建物表示は機能受入とするが、30 FPSを必須とする
本番構成にはLOD／SSE、表示解像度、建物ソースまたは下段表示方針の追加最適化が必要である。

### 13.3 Maprayを主役とするデータ構成

今回の下段広域表示は、まず5km Three.js表示の成立性を確認するためのPLATEAU公開3D Tiles
プロトタイプである。一方、上段Maprayは既にMapray OpenTilesの東京B3D
（`533935`、`533945`）を`StandardB3dProvider`で表示しており、Maprayデモとしての主要な
広域建物表示はMapray経路に載っている。

Mapray CloudへCityGMLを登録するBuilding Datasetの生成物は、一般の3D Tilesではなく
Mapray JS用のB3Dである。したがって本番構成では、独自または更新版CityGMLが必要になった時点で
Mapray Cloudへ必要範囲だけを登録し、上段MaprayのB3D Dataset IDを差し替える。B3Dを下段
Three.jsへ直接読み込む公開ローダー契約は採用せず、下段は広域確認用PLATEAU 3D Tilesと、
既存600mシミュレーション資産を担当する。この二段階方針により、Mapray Cloudへのアップロードと
認証情報がなくても先に表示・性能を検証できる。

`5km overview`は上段Maprayと下段Three.jsをともに広域へ、`Incident`と`600m detail`は下段を
局所へ切り替える。ドローン選択・追従でも局所へ戻る。二つの建物群は同時表示せず、中央600mでの
重複描画とZ-fightingを避ける。MuJoCoの物理計算経路には変更を加えていない。

実ブラウザ確認では、既存のfixture URLを使い、次を確認する。

1. 初期状態または`5km overview`で下段バッジが`WIDE 5km / PLATEAU LOD1 STREAMING`となる。
2. 下段に5km地面と中央600m外の建物が表示される。
3. `600m detail`で既存の地形・801棟へ切り替わり、バッジが`LOCAL 600m / PLATEAU LOD1 + MuJoCo`となる。
4. 再度`5km overview`を押すと広域へ戻る。
5. 開発者コンソールとNetworkに3D TilesのCORS／404エラーがなく、操作時FPSが許容範囲である。

### 13.4 Origin-01機体と飛行視認性（2026-08-13）

下段Three.jsの機体を、`hakoniwa-godot-drone-courses_4_1/Models/Origin-01`の
`origin-01.glb`と`propeller_origin_01.glb`へ変更した。GLB内のJPEGテクスチャは埋め込み済みで、
元リポジトリはHakoniwa CommunityのMIT Licenseである。実行時に別ワークスペースへ依存しないよう、
2個のGLBとライセンス本文だけをWeb3D側へ複製した。Godot側の`DRONE_SCALE=0.6`、機体の180度向き、
4ローター位置、およびプロペラモデルの合成縮尺0.216をThree.js設定へ移植している。元のGodot
プロジェクトは変更していない。

5km俯瞰では実寸約1mの機体が画面上で1ピクセル未満となるため、機体メッシュを単純に拡大する方式は
採用しない。物理上の寸法と600m詳細表示を維持したまま、下段へ次の運航表示を追加した。

- 全機: シアンの照準型マーカーと高度方向ビーコン
- 選択機: 黄色の名称付きマーカー、点滅強調、約90秒分の飛行軌跡
- 5km: マーカーを広域用サイズへ切替。Origin-01は運航視認用に表示倍率120倍で併記
- 600m: マーカーを小さくし、Origin-01を視認用倍率12倍、回転プロペラ付きで表示

選択機IDは上段・一覧と同じ`flightStateStore`からThree.js公開APIへ同期する。したがって5kmへ戻しても
選択機の強調は維持される。機体選択だけでは5km／600mの表示範囲を変更せず、`5km overview`、
`Incident`、`600m detail`の明示操作だけで範囲を切り替える。局所表示中に追従が有効な場合は、
選択機へカメラを追従させる。

初回確認でOrigin-01設定に前方カメラ定義がなく小窓が消えていたため、従来と同じ30%サイズの
前方カメラを追加した。設定JSONには版付きURLを付け、旧設定がブラウザキャッシュから再利用される
ことを防ぐ。機体の広域・局所表示倍率はカメラ階層には掛けず、映像位置への影響を避ける。

確認21では、手動デモ開始35秒後の自動Incident選択と自動カメラツアーが、ユーザーの機体選択と
重なって5kmから600mへ強制遷移していた。通常のデモではインシデントを記録するだけに変更し、
選択中の機体と表示範囲を維持する。従来の自動Incident→600m→5kmツアーが必要な場合だけ、URLへ
`autoCameraTour=1`を指定する。

既存3経路は全長約9.38km、9.58km、13.16kmを240／260／300秒で周回しており、速度は約
36.8～43.9m/s（時速133～158km）だった。デモで軌跡を追える約12m/sを目標に、周回時間を
780／800／1100秒へ変更した。飛行座標、経路形状、高度、MuJoCo物理経路は変更していない。

実ブラウザでは次を確認する。

1. 機体プロファイルが`Origin-01 (bundled)`になり、600mで従来機体ではなくOrigin-01が表示される。
2. `5km overview`で全30機のシアンマーカーが見え、選択機だけが黄色の名称付き表示になる。
3. 30秒以上飛行させると、選択機の黄色い軌跡から移動方向と経路を追える。
4. `600m detail`またはドローン選択で、マーカーが小さくなりOrigin-01実寸モデルが戻る。
5. 飛行速度が従来より約3分の1となり、広域・局所の双方で移動を目視追跡できる。

## 14. 参照

### リポジトリ内

- `Plan20260811/mapray-wide-area-operations-demo-plan.md`
- `Plan20260811/handover-20260812.md`
- `Plan20260811/phase-c-verification.md`
- `hakoniwa-geo-viewer/README.md`
- `hakoniwa-geo-viewer/config/operations/shibuya-wide-area-5km.geojson`
- `hakoniwa-geo-viewer/src/client/src/mapray_layer.js`
- `runtime/windows/scenarios/shibuya/city-pipeline.json`
- `runtime/windows/generated/shibuya/manifest.json`
- `runtime/windows/generated/shibuya/terrain-manifest.json`
- `plan20260806/phase-w4-result.md`

### 公式情報

- Mapray Building Dataset: <https://mapray.com/documents/mapray-cloud/datasets/b3d/>
- Mapray Building表示: <https://mapray.com/documents/mapray-js/guides/tiles-and-layers/building/>
- Mapray Cloud API B3D: <https://resource.mapray.com/doc/cloudapi/index.html>
- Mapray PLATEAU 3D Tilesサンプル: <https://mapray.com/documents/mapray-js/examples/current/objects/display_plateau_3dtiles/>
- Mapray attribution: <https://mapray.com/documents/introduction/attribution/>
- PLATEAU CityGMLの標高と楕円体高: <https://www.mlit.go.jp/plateau/learning/tpc03-4/>
- PLATEAU-Terrainの高さ基準: <https://docs.plateauview.mlit.go.jp/datasets/terrain/>
- 国土地理院 測量計算API: <https://vldb.gsi.go.jp/sokuchi/surveycalc/api_help.html>
- PLATEAUデータカタログAPI: <https://docs.plateauview.mlit.go.jp/api/rest/operations/datacatalogplateau-datasets/>
- PLATEAU 3D Tiles／MVT: <https://docs.plateauview.mlit.go.jp/datasets/3d-tiles/>
- PLATEAU CityGML検索API: <https://docs.plateauview.mlit.go.jp/api/rest/operations/datacatalogcitygmlconditions/>
- PLATEAU最新CityGML URL: <https://docs.plateauview.mlit.go.jp/api/rest/operations/datacatalogcitygmlspeccitygmlzip/>
- 東京タワー公式所在地: <https://www.tokyotower.co.jp/company/>
