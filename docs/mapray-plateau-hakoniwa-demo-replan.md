# Mapray × PLATEAU × 箱庭 ドローンデモ再計画

作成日: 2026-08-14  
対象ワークスペース: `D:\work_hako\work_mapray`  
対象シナリオ: 東京タワー周辺  
文書の目的: デモの価値仮説、比較条件、実装順序、検証方法を再定義する  
位置付け: `Plan20260811/mapray-wide-area-operations-demo-plan.md` の「広域対局所」を主軸とした説明を置き換える再計画

## 1. 結論

新しいデモの主題を次に固定する。

> **大容量のPLATEAU都市モデルと防災・点検情報をMaprayで滑らかに可視化し、その都市空間上で箱庭コアが数十機のドローン運航状態をリアルタイムに駆動する。**

デモでは、以下の二つを別の比較モードとして明確に証明する。

1. **表示・配信方式の比較**
   - 同じPLATEAU原典をMapray向けに変換・配信・描画した場合と、標準的なWeb向け形式を別レンダラーで表示した場合を比較する。
   - 高速性を宣伝文句だけで主張せず、読み込み時間、フレーム時間、長時間フレーム、転送量等を実測する。
2. **実行主体の比較**
   - ブラウザ内で作ったアニメーションと、箱庭コアからPDUで受信するリアルタイム状態を同一表示条件で比較する。
   - 箱庭コアの停止、切断、再開、指令による経路変更を画面で確認できるようにする。

現在の上下2分割レイアウトは廃止しない。ただし、一画面で二つの論点を同時に説明せず、次のモードに分ける。

- `RENDERING A/B`: 上段Mapray、下段比較対象。表示・配信方式を比較する。
- `MISSION / RUNTIME`: 上段Mapray運用画面、下段選択機の詳細／物理画面。Browser StandaloneとHakoniwa Coreを比較する。

「Maprayは広域、Three.jsは局所」という使い分けを主メッセージにはしない。表示範囲を広げる操作は、用途の違いを示すためではなく、データ量を段階的に増やす負荷試験として使用する。

## 2. 再調査で確認した事実

### 2.1 Maprayが公式に示している価値

[Mapray公式サイト](https://mapray.com/)は、主な特長として以下を挙げている。

- PLATEAU東京23区全域、約600 km²・40 GB規模の3D都市モデルをブラウザ上で高速かつ高精細に描画できる。
- 水量や地形の変化を、時間や色を使って可視化できる。
- 座標合わせ、データの間引き、分割等の前処理負担を減らせる。
- Mapray Cloudが地理空間データを最適化・管理・配信し、Mapray JSが大規模3Dデータをレンダリングする。
- 防災、景観シミュレーション、設備点検を活用例としている。

ただし、東京23区40 GBの性能はMaprayによる公式説明であり、本プロジェクト自身の実測結果ではない。デモでは「公式にそう書かれている」ことと「このPC・このデータで測った結果」を分ける。

### 2.2 CityGMLからMapray向けBuildingデータを作れる

[Mapray Buildingデータセット](https://mapray.com/documents/mapray-cloud/datasets/b3d/)では、大規模3DデータとしてCityGMLをMapray Cloudへ登録し、`StandardB3dProvider`からMapray JSへ配信する手順が示されている。[Building表示ガイド](https://mapray.com/documents/mapray-js/guides/tiles-and-layers/building/)では、B3DシーンのLOD factorを調整できる。

したがって、本デモで検証すべき価値は「PLATEAUそのものとの優劣」ではなく、次のパイプライン全体である。

```text
PLATEAU CityGML
    ↓
Mapray Cloudによる変換・最適化・配信
    ↓
Mapray JSによる都市・地形・動的情報の統合描画
```

### 2.3 PLATEAU側にもWeb表示用の最適化形式がある

[PLATEAU配信サービス](https://docs.plateauview.mlit.go.jp/datasets/3d-tiles/)は、CityGMLを3D TilesまたはMVTへ変換して配信している。PLATEAU VIEWもブラウザ上で3D都市モデルを表示する。

このため、以下の比較は禁止する。

- 生のCityGMLをそのままブラウザへ読み込む構成とMaprayを比較する。
- 小さく簡略化した比較画面と、高精細なMapray画面を比較して性能差を主張する。
- 異なる年度、範囲、LOD、テクスチャ有無のデータを比較してMaprayの優位とする。
- 「PLATEAUは重い」「Maprayなら軽い」と、PLATEAU全体に一般化する。

最終的な表現は、以下のように正確にする。

> 同一のPLATEAU原典を、Mapray B3D/Mapray JSの配信・描画経路と、標準Web配信経路で比較した結果、この条件では○○という差が確認できた。

### 2.4 Mapray自身もPLATEAU 3D Tilesを表示できる

最新のMaprayドキュメントには、PLATEAUの3D Tilesを`Standard3DTileProvider`で表示する[実験的サンプル](https://mapray.com/documents/mapray-js/examples/current/objects/display_plateau_3dtiles/)がある。これにより将来は、同一レンダラー内でB3Dと3D Tilesを比較できる可能性がある。

ただし、現在のプロジェクトはMapray JS `0.9.6`を主に使用しており、この3D Tiles機能は最新の実験パッケージである。現行デモへ直接使えるとは判断しない。SDK更新を伴う比較は、最初の技術スパイクで可否を確認する。

### 2.5 防災・点検とドローンの組み合わせには実例がある

PLATEAUの[ドローンを用いたインフラ管理システム](https://www.mlit.go.jp/plateau/use-case/uc23-20/)では、3D都市モデル上で点検経路、撮影データ、静的・動的リスクを統合し、鉄道設備点検に利用している。PLATEAUの[災害リスク情報の3D可視化](https://www.mlit.go.jp/plateau/use-case/uc20-011/)では、浸水想定区域を3D都市モデルへ重ね、防災判断へつなげている。

したがって、「都市インフラの災害後点検」はMaprayの可視化能力、PLATEAUの都市情報、箱庭のドローン運航を無理なく結ぶシナリオである。

### 2.6 Maprayの水・地形・3Dモデル機能にはバージョン制約がある

- [WaterPolygonEntityサンプル](https://mapray.com/documents/mapray-js/examples/current/entities/add_water_polygon/)は水面ポリゴンを表示できる。
- [地形変化アニメーション](https://mapray.com/documents/mapray-js/examples/current/heightmap/anime_region_contour/)は二つのheightmapを補間し、時系列の地形変化を色と高さで表示できる。
- [ModelEntityガイド](https://mapray.com/documents/mapray-js/guides/entities/model/)は3Dモデルの位置、姿勢、スケールを制御できるが、現行ドキュメントではモデルをMapray Cloudへ登録する必要がある。

これらは最新SDKまたは実験機能を含む。現在の`0.9.6`で利用可能と仮定せず、SDK方針を決めてから実装する。

### 2.7 性能は実行環境に依存する

[Mapray動作環境](https://mapray.com/documents/introduction/system-requirements/)はWebGL 2.0を必要とし、大容量データを快適に表示するにはネットワーク、CPU、GPU、メモリの条件が影響すると説明している。

性能結果には最低限、次を付記する。

- OS、ブラウザとバージョン
- CPU、GPU、メモリ
- 画面解像度、device pixel ratio
- Mapray SDK版
- データ年度、範囲、LOD、テクスチャ有無
- ネットワーク条件
- キャッシュ状態
- 機体数と状態更新周期

## 3. デモの目的と非目的

### 3.1 目的

1. PLATEAU都市モデルをMapray用に変換・配信したときの表示品質と応答性を、比較可能な条件で示す。
2. 30機を基本としたドローン状態、航跡、点検対象、危険区域を都市モデル上で読み取りやすく表示する。
3. 防災・設備点検という業務ストーリーの中で、都市データとリアルタイム状態を重ねる価値を示す。
4. Browser StandaloneとHakoniwa Core/PDUの違いを、停止・再開・切断・指令反映という挙動で示す。
5. 宣伝上の主張ではなく、再現可能な実測JSONと実行手順を残す。

### 3.2 非目的

- MaprayがPLATEAUより優れていると一般化すること。
- Maprayが物理シミュレーションや衝突判定を行うと説明すること。
- 30機のkinematic状態を30機のMuJoCo物理E2Eと説明すること。
- 東京タワー600mのMuJoCoコンパイル成功だけで、飛行・衝突・制御が動作確認済みとすること。
- 合成した浸水データを実際の災害予測やハザード情報として見せること。
- 比較条件が異なる状態でFPSや転送量だけを並べること。

## 4. デモで証明する主張

| 主張 | 画面またはログで必要な証拠 | 未達時の扱い |
|---|---|---|
| Mapray経路は大容量都市データを滑らかに扱える | 同一データ条件でのFPS、フレーム時間、Long Task、読み込み時間 | 性能優位を主張しない |
| 高精細な都市と多数機を同時表示できる | 東京タワーへの接近表示、30機の位置更新、10分安定性 | 機体数または表現LODを下げて明記 |
| Maprayは防災・点検情報を統合できる | 危険区域、点検対象、航跡、状態色、時系列レイヤ | 単なる都市ビューワとして評価 |
| 箱庭コアはブラウザアニメーションと異なる | PDU sequence、core時刻、停止・再開、切断表示、指令反映 | `LIVE`表示をしない |
| 600m物理環境と地理表示が整合する | 原点、軸、高度、選択機位置、地形・建物の対応 | 物理詳細画面を参考表示とする |

## 5. デモ構成

### 5.1 モード1: `RENDERING A/B`

目的は、同一PLATEAU原典を異なるWeb配信・描画経路で表示したときの差を確認することである。

```text
上段 A: PLATEAU CityGML → Mapray B3D → Mapray JS
下段 B: 同一CityGML → 標準3D Tilesまたは同等の比較形式 → 比較レンダラー
```

#### 必須の同期条件

- カメラ位置、注視点、画角
- 表示範囲
- PLATEAU年度と抽出範囲
- 建物LODとテクスチャ条件
- 地形と航空写真の有無
- ドローンID、位置、姿勢、更新周期
- 航跡長、ラベル、危険区域
- 画面サイズとdevice pixel ratio

#### UI

- `600 m`、`1.2 km`、`2.4 km`のデータ負荷切り替え
- `0`、`30`、`50`、`100`機の表示負荷切り替え
- `Cold/Warm`キャッシュ条件表示
- データ名、年度、LOD、テクスチャ、フォーマット表示
- `FPS median`、`p95 frame time`、`Long frames`、`TTFF`、`Transferred bytes`
- 計測値が取得できない場合は`N/A`とし、推定値を表示しない

#### 重要な計測原則

上下2画面を同時に動かす状態は、GPU、CPU、ネットワークを奪い合う。そのため、2分割画面は目視比較用とし、正式な性能値は以下の順番で取得する。

1. Mapray画面だけを全画面で実行する。
2. 比較画面だけを同じ解像度で実行する。
3. 同じカメラ操作スクリプト、機数、時間で測定する。
4. 各条件を最低3回実行し、中央値を採用する。
5. その結果だけを2分割画面の結果パネルへ読み込む。

### 5.2 モード2: `MISSION / RUNTIME`

シナリオ名を次とする。

> **東京タワー周辺・災害後都市インフラ緊急点検**

上段はMaprayを主画面として都市、点検対象、危険区域、全機状態を表示する。下段は選択機の3D詳細、カメラ視点、600m地形、MuJoCo対応建物を表示する。

#### デモ進行

1. 東京タワー周辺のPLATEAU都市モデルを表示する。
2. 防災レイヤを有効化し、危険区域と点検優先設備を色分けする。
3. 30機のドローンを待機地点から出動させる。
4. 全機をMapray上で追跡し、航跡、任務、警告を表示する。
5. 危険区域へ接近した機体または異常を検出した機体を強調する。
6. 対象機を選択し、下段を同じ機体の詳細表示へ切り替える。
7. Hakoniwa Coreを一時停止し、画面上の時刻と全機更新が止まることを示す。
8. 再開後に点検指令を変更し、担当機または経路がPDU経由で変わることを示す。
9. Bridge切断時は`STALE/DISCONNECTED`を表示し、最後の受信状態をライブ状態と誤認させない。

### 5.3 防災レイヤの段階

防災機能は、データの正確性とSDKの実現性に応じて段階導入する。

#### MVP

- 点検対象設備
- 進入禁止区域
- 高度制限区域
- 損傷想定地点
- 機体状態と点検進捗

#### 拡張

- 時刻スライダー付き浸水深表示
- 水面または色付き高さポリゴン
- 地形差分の色表示
- 点検前後の画像、点群、損傷位置の重畳

浸水や地形差分に合成データを使う場合は、常に`SIMULATED HAZARD`と表示する。東京タワー周辺で実在ハザードを扱う場合は、出典、基準時点、利用条件をデータマニフェストへ記録する。

## 6. ドローン表示方針

### 6.1 比較モード

都市配信性能を比較するときは、ドローン表現を両画面で同一にする。

- 最初は同じ単純形状またはbillboardを使う。
- 同じID、色、サイズ、更新頻度、航跡点数にする。
- 上段だけピン、下段だけ詳細3Dモデルという比較は行わない。
- 3Dモデルの表示負荷は都市データ負荷と分けて計測する。

### 6.2 運用モード

多数機を読み取りやすくするため、表示距離に応じて表現を切り替える。

- 遠距離: アイコン、状態色、警告だけ
- 中距離: ID、高度、航跡、任務状態
- 近距離または選択機: 3Dドローンモデル、姿勢、進行方向

Mapray上の3Dモデルは、現行SDK、Cloud登録、更新性能を技術スパイクで確認する。利用できない場合は、Mapray側で3D機体を無理に実装せず、選択機を明確な航空機アイコンと姿勢矢印で表現し、制限として記録する。

## 7. Browser StandaloneとHakoniwa Coreの比較

### 7.1 同じにするもの

- 表示データ
- 機数
- 初期位置
- 経路とイベント時刻
- 状態配信周期
- カメラ操作
- 軌跡上限

### 7.2 異なるもの

| 項目 | Browser Standalone | Hakoniwa Core |
|---|---|---|
| 時刻 | ブラウザ内時計 | 箱庭コア時刻 |
| 状態生成 | fixture/決定論的生成 | PDU受信 |
| 停止・再開 | UI内の再生制御 | コアのライフサイクル |
| 指令 | ブラウザ内状態変更 | コア／アセットへ送信しPDUで反映 |
| 切断 | 該当なし | stale、sequence停止、再接続 |
| 再現性 | seedとfixture | core設定、PDUログ、seed |

### 7.3 現在の正確な到達点

- 東京タワーを選択できるcore fleetランチャーはローカル変更として存在する。
- 30機のPDU受信とsequence進行はkinematic publisherで確認済みである。
- これは30機のMuJoCo物理シミュレーションではない。
- 東京タワー600m環境はMuJoCo XMLのコンパイルに成功しているが、飛行・制御・衝突のE2E確認は別途必要である。

### 7.4 物理忠実度の段階

1. `KINEMATIC FLEET`: 30機の運航・通信・表示負荷を確認する。
2. `MIXED FIDELITY`: 選択した1機だけをMuJoCo詳細、残りをkinematicとする。
3. `FULL PHYSICS FLEET`: 複数機MuJoCoが実測基準を満たした場合だけ採用する。

デモ画面には必ず現在の段階を表示する。

## 8. データと比較対象の選定

### 8.1 データマニフェスト

両経路の入力が同一であることを証明するため、以下をJSONとMarkdownで残す。

- 原典CityGMLのファイル名、年度、自治体、メッシュコード
- SHA-256
- 抽出bboxと原点
- 建物数、三角形数、テクスチャ数と容量
- LOD
- 高度基準と座標系
- Mapray Dataset ID、変換完了日時、出力形式
- 比較形式の変換ツール、版、引数
- 配信URLとAttribution

### 8.2 比較対象候補

技術スパイクでは次の二候補を試し、最終デモでは一つに絞る。

1. **標準PLATEAU 3D Tiles系**
   - 比較として最も公平で説明しやすい。
   - 現在のThree.js画面へ3D Tilesローダーを追加するか、Cesium等を採用する必要がある。
2. **現在のThree.js直接メッシュ系**
   - 既存資産を再利用でき、実装コストが低い。
   - 「一般的な直接実装の一例」であり、PLATEAU標準配信全体を代表しないと明記する必要がある。

採用基準は、同一入力を再現できること、メトリクスを取得できること、デモPCで安定すること、説明が誤解を生まないことである。

## 9. 性能検証計画

### 9.1 測定項目

- viewer初期化時間
- first useful frameまでの時間
- 都市モデルが操作可能になるまでの時間
- `requestAnimationFrame`によるFPS中央値
- p95/p99フレーム時間
- 50 ms以上のLong TaskまたはLong Animation Frame
- Resource Timingで取得可能な転送量とリクエスト数
- Chromiumで取得可能な場合のJS Heap
- 表示機体数、状態更新数、欠落・重複数
- PDU生成時刻から画面反映までの遅延
- WebGL context lost、例外、OOM

[MDN Performance API](https://developer.mozilla.org/en-US/docs/Web/API/Performance_API)と[Long Animation Frames](https://developer.mozilla.org/en-US/docs/Web/API/Performance_API/Long_animation_frame_timing)を参考に、`PerformanceObserver`を優先する。

### 9.2 制約の扱い

- Cross-Origin Resource Timingで`transferSize`が取得できない場合は0を実転送量と解釈しない。
- 必要であればHARまたはサーバーログを別証拠にする。
- `performance.memory`はChromium依存値として扱い、全ブラウザ共通指標にしない。
- Mapray内部タイル数は公開APIで取得できる場合だけ記録し、非公開APIへ依存しない。
- 同一ページ内のMapray FPSとThree.js FPSを架空に分離しない。

### 9.3 試験マトリクス

| 軸 | 条件 |
|---|---|
| 表示経路 | Mapray、比較対象 |
| キャッシュ | cold、warm |
| 範囲 | 600 m、1.2 km、2.4 km |
| 機数 | 0、30、50、100 |
| 状態生成 | fixture、core kinematic |
| カメラ | 固定俯瞰、東京タワー接近、選択機追従 |
| 時間 | 2分ウォームアップ、10分測定 |
| 反復 | 各主要条件3回以上 |

全組み合わせを初回から実行しない。まず600 mの0機・30機、cold/warmで計測系を検証し、その後に範囲と機数を増やす。

### 9.4 合格基準

#### 技術的合格

- 30機、10分間でクラッシュ、OOM、WebGL context lost、未処理例外がない。
- ページFPS中央値30以上、p95 frame time 50 ms未満を基本目標とする。
- 軌跡上限到達後にEntity数とメモリが時間比例で増え続けない。
- core kinematicで機体ID欠落・重複がなく、sequenceが単調増加する。
- カメラ、機体状態、比較条件が両経路で一致する。

#### デモ主張の合格

- Mapray経路に、視認可能で再現性のある性能または運用上の利点が一つ以上ある。
- 差は最低3回の中央値で示し、単発の最良値を使わない。
- 有意な差が出ない場合は「高速化」をデモの主張から外す。
- 比較対象の劣化設定を作ってMaprayを有利にしない。

### 9.5 二種類の性能結果

ネットワークとクラウド配信を含む結果と、レンダリング負荷をできるだけ揃えた結果を分ける。

- `End-to-End`: サービス配信、ネットワーク、デコード、描画を含む利用者体験。
- `Warm/Render-oriented`: warm cacheを使い、主に描画と動的重畳の差を見る。

この区別により、配信CDNの差をレンダラー性能と誤認しない。

## 10. 実装フェーズ

### Phase 0: 現状固定と未コミット変更の整理

目的: 今日までの変更を失わず、新計画と混在させない。

- `hakoniwa-geo-viewer`のローカルブランチ`agent/demo-comparison-core-tokyo`に未コミット変更がある。
- 変更対象は比較UI、状態生成元表示、同期カメラ、テスト、READMEである。
- ルート側に東京タワー対応core launcherとruntime testの変更がある。
- 次回、差分をレビューして「再利用」「修正」「破棄」をファイル単位で決める。
- 性能デモの条件が確定するまでPR、Mergeは行わない。

成果物:

- 差分インベントリ
- 再利用判断表
- 新計画用作業ブランチまたは明確なcheckpoint commit

### Phase 1: 比較可能性スパイク

目的: 本格実装前に、同一データ比較とMapray機能の実現性を測る。

1. 東京タワー600 m原典のデータマニフェストを作成する。
2. Mapray B3Dと比較形式が同一入力か確認する。
3. Mapray `0.9.6`継続と最新SDK評価の二経路を整理する。
4. PLATEAU 3D Tiles比較の最小表示を試す。
5. Mapray上の3Dドローンモデル更新を1機、30機で試す。
6. 水面、色付き高さ、heightmap animationの利用可否を試す。
7. 最小性能モニターで600 m、0機・30機を測る。

Go条件:

- 同一入力で比較できる。
- 少なくとも一つの公平な比較対象が動く。
- Mapray機能とSDKの採用範囲を確定できる。
- 実測値を取得できる。

No-Go時:

- 性能比較の実装を止め、Maprayの統合可視化とCloud前処理価値に焦点を変更する。
- 取得不能な最新SDK機能をデモ予定から除外する。

### Phase 2: `RENDERING A/B`実装

- 上下の同期カメラと同期機体状態
- 同一データ条件表示
- 単独ベンチマークランナー
- JSON結果出力
- 結果パネル
- cold/warm手順
- 3回測定と中央値集計
- 誤解を防ぐラベルとAttribution

完了条件:

- 別の開発者が手順どおり実行して同じ比較を再現できる。
- 2分割画面の数値が単独実行結果から読み込まれている。
- 実測していない数値が画面に存在しない。

### Phase 3: `MISSION / RUNTIME` MVP

- 東京タワー周辺の点検対象と危険区域
- 30機kinematic fleet
- 適応的な機体表示
- 航跡、任務状態、警告
- 選択機同期
- Browser Standalone/Core切り替え
- PDU sequence、core時刻、接続状態
- core停止・再開・切断表示
- 点検指令または経路変更

完了条件:

- 観客が「都市データ」「多数機」「危険区域」「点検対象」の関係を一画面で理解できる。
- BrowserとCoreの違いが説明を聞かなくても状態表示と挙動で分かる。

### Phase 4: 防災ビジュアライゼーション

- データ出典を決める。
- 実データまたは`SIMULATED HAZARD`を明記した合成データを用意する。
- 水量・危険度・地形差分の一つを時系列表示する。
- 危険度変化を機体経路または点検優先度へ反映する。

優先順位は「見栄え」ではなく「判断が変わること」とする。水面だけを装飾として追加しない。

### Phase 5: 600 m MuJoCo詳細統合

- 選択した1機の飛行・制御を確認する。
- 地形、建物、原点、軸、高度基準をMapray/Three.js/MuJoCoで照合する。
- 衝突または接近イベントをPDUへ出す。
- mixed-fidelity表示を実装する。
- 複数機MuJoCoは性能検証後の追加項目とする。

### Phase 6: デモ固定・レビュー・公開判断

- 固定seedと固定進行
- 5分以内の本番台本
- オフライン／通信障害時の代替
- Attribution、ライセンス、Mapray利用条件確認
- 実測レポートとスクリーンショット
- ユーザー目視確認
- その後にcommit、push、Draft PR、レビュー、Merge

## 11. デモ台本案

### 11.1 技術証明: 約2分

1. 同一PLATEAUデータであることを画面に表示する。
2. Mapray経路と比較経路を同じ東京タワーカメラで表示する。
3. 600 mから1.2 kmへ負荷を増やす。
4. 0機から30機へ変更する。
5. 事前の単独ベンチマーク結果を表示する。
6. 「このPC・このデータ・この条件での結果」と説明する。

### 11.2 業務価値: 約3分

1. `MISSION / RUNTIME`へ切り替える。
2. 災害後の点検対象と危険区域を表示する。
3. Browser Standaloneで予定済みの30機運航を示す。
4. Hakoniwa Coreへ切り替え、PDU時刻とsequenceを示す。
5. コアを停止し、全機状態が停止することを示す。
6. 再開後、危険区域を避ける点検指令を出す。
7. 対象機を選び、下段の詳細画面で機体・地形・設備を確認する。
8. Maprayが大規模都市と業務情報の統合、箱庭が動的状態の正本を担当するとまとめる。

## 12. リスクと対策

| リスク | 影響 | 対策 |
|---|---|---|
| Maprayと標準3D Tilesに大きな性能差が出ない | 主メッセージが成立しない | 性能優位を外し、Cloud変換、GIS統合、可視化APIの価値へ切り替える |
| 比較データが同一でない | 結果の信頼性を失う | マニフェストとSHA-256を必須化する |
| Mapray最新機能が0.9.6で使えない | 水・3D機体が実装できない | Phase 1でSDK版を決め、代替表現を用意する |
| Mapray ModelEntityで30機更新が重い | 多数機が滑らかに見えない | 遠距離icon、近距離modelのLOD表示にする |
| 2分割計測が相互干渉する | 不正確な性能値になる | 正式計測は単独実行する |
| Cross-Originで転送量が取れない | 配信効率を測れない | HAR、サーバーログ、N/A表示を使う |
| kinematic fleetを物理fleetと誤認する | デモの信頼性を失う | `KINEMATIC`、`MIXED`、`MUJOCO`を常時表示する |
| 合成災害データを実データと誤認する | 業務上危険 | `SIMULATED HAZARD`と出典を表示する |
| Mapray Cloud容量・利用条件 | データ登録や公開が止まる | 無料枠・契約・AttributionをPhase 1で確認する |
| ネットワーク依存 | 本番でロード失敗 | warm cache、録画、replay、縮小データを代替として準備する |

## 13. 優先順位

### Must

- 同一PLATEAU原典による公平な比較
- 単独実行による実測
- 30機kinematicの安定表示
- Mapray上の危険区域・点検対象・航跡
- Browser/Coreの停止・再開・切断差
- データ種別、SDK版、物理忠実度の明示

### Should

- 距離に応じた3Dドローン表示
- 時系列の防災レイヤ
- 点検指令による経路変更
- mixed-fidelityの選択機MuJoCo

### Could

- 50機、100機stress test
- 点群や点検画像の重畳
- 実浸水シミュレーション連携
- 全機MuJoCo物理
- Mapray最新実験SDKへの移行

## 14. 次回の開始点

次回は実装から始めず、Phase 0とPhase 1のうち以下だけを行う。

1. 現在の未コミット差分をファイル単位でレビューする。
2. 東京タワー600 mのMapray B3DとThree.js/PLATEAU資産の原典一致を確認する。
3. データマニフェストを作成する。
4. 比較対象を「標準3D Tiles」または「現在のThree.jsメッシュ」から選ぶための最小スパイクを行う。
5. Mapray SDK `0.9.6`継続か最新SDK評価かを決める。
6. 600 m、0機・30機の最小実測を行い、Go/No-Goを判断する。

この判断が終わるまで、本番UIの作り込み、防災演出、PR作成は行わない。

## 15. 参考資料

2026-08-14に確認した公式資料を優先している。

### Mapray

- [Mapray デジタルツイン開発プラットフォーム](https://mapray.com/)
- [Maprayとは / Mapray JSとMapray Cloud](https://mapray.com/documents/introduction/)
- [動作環境](https://mapray.com/documents/introduction/system-requirements/)
- [Buildingデータセット](https://mapray.com/documents/mapray-cloud/datasets/b3d/)
- [Building表示とLOD](https://mapray.com/documents/mapray-js/guides/tiles-and-layers/building/)
- [B3Dで東京を表示するサンプル](https://mapray.com/documents/mapray-js/examples/current/objects/display_3d_building_all_tokyo/)
- [PLATEAU 3D Tiles表示サンプル（実験機能）](https://mapray.com/documents/mapray-js/examples/current/objects/display_plateau_3dtiles/)
- [WaterPolygonEntityサンプル](https://mapray.com/documents/mapray-js/examples/current/entities/add_water_polygon/)
- [地形変化アニメーション](https://mapray.com/documents/mapray-js/examples/current/heightmap/anime_region_contour/)
- [ModelEntity](https://mapray.com/documents/mapray-js/guides/entities/model/)
- [DEM Layerの重ね合わせ](https://mapray.com/documents/mapray-js/guides/tiles-and-layers/dem-layer/how-to-stack/)

### PLATEAU

- [PLATEAU配信サービス概要](https://docs.plateauview.mlit.go.jp/intro/)
- [PLATEAU 3D Tiles / MVT](https://docs.plateauview.mlit.go.jp/datasets/3d-tiles/)
- [PLATEAU可視化用データ変換仕様](https://docs.plateauview.mlit.go.jp/spec/visualization/)
- [ドローンを用いたインフラ管理システム](https://www.mlit.go.jp/plateau/use-case/uc23-20/)
- [3D都市モデルとBIMを活用したモビリティ自律運航](https://www.mlit.go.jp/plateau/use-case/uc23-17-1/)
- [災害リスク情報の3D可視化](https://www.mlit.go.jp/plateau/use-case/uc20-011/)

### Web性能計測

- [MDN Performance APIs](https://developer.mozilla.org/en-US/docs/Web/API/Performance_API)
- [MDN Long Animation Frame timing](https://developer.mozilla.org/en-US/docs/Web/API/Performance_API/Long_animation_frame_timing)
- [MDN PerformanceLongTaskTiming](https://developer.mozilla.org/en-US/docs/Web/API/PerformanceLongTaskTiming)

## 16. 最終判断

本デモは、見た目の上下比較だけでは成立しない。成功条件は、次の三つを一貫した証拠で示すことである。

1. **同一のPLATEAUデータをMaprayの変換・配信・描画経路へ載せると、この条件でどのような効果が出るか。**
2. **その都市空間へ数十機の状態と防災・点検情報を重ねても、運用判断に使える形で表示できるか。**
3. **ブラウザ内アニメーションではなく、箱庭コアの時刻とPDUが表示を駆動していることを挙動で証明できるか。**

最初に測定し、結果に合わせて主張を決める。Maprayが有利に見える条件を後から作るのではなく、同じデータと同じ操作で得られた差だけをデモの価値として採用する。
