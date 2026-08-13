# Phase D 運航判断A/B評価手順

## 目的と現在の状態

30機・同一難度の計画経路逸脱を、Mapray＋Three.jsとLeaflet＋Three.jsで比較する。
評価基盤、固定seed、正解データ、回答・計測UI、CSV/JSON出力、集計・判定ツールは実装済み。
人による評価は未実施であり、最低3名、目標5名の結果が揃うまでPhase Dの最終判定は行わない。

## 評価条件

- 匿名の評価者IDのみを使う。個人名は入力しない。
- 1人がMapray条件とLeaflet条件を1回ずつ行う。
- 奇数IDはMapray先行、偶数IDはLeaflet先行にし、順序効果を相殺する。
- 各条件は30機、ブラウザ合成fixture、固定seedで実施する。
- 異常発生前は正解地点を表示しない。
- 評価中は自動カメラ移動と異常機の自動選択を無効にする。
- Mapray条件でMaprayが初期化できなければ開始できない。Leafletへの暗黙フォールバックをMapray結果として記録しない。

割付は次のとおり。

| 評価者 | 1試行目 | 2試行目 |
|---|---|---|
| P01、P03、P05 | Mapray / `D-SEED-A` / seed `20260821` | Leaflet / `D-SEED-B` / seed `20260822` |
| P02、P04 | Leaflet / `D-SEED-A` / seed `20260821` | Mapray / `D-SEED-B` / seed `20260822` |

## 事前準備

ワークスペース直下でViewerサーバーを起動する。

```powershell
python scripts\windows\serve_geo_viewer.py --directory . --port 18080 --bind 0.0.0.0 --env-file runtime\windows\config\.env
```

Mapray条件では`runtime\windows\config\.env`にMapray API Keyが必要。URLや評価結果へKeyは保存しない。

## 1試行の進め方

評価者へ、次のタスクだけを伝える。正解seedや正解表は見せない。

1. 異常が発生した機体IDを特定する。
2. 異常種別を答える。
3. 異常地点が600m詳細地区のどの位置かを特定する。
4. 対象機とインシデントを選択し、`600m detail`からThree.js局所解析へ移る。
5. 回答、迷った回数、確信度、短い所感を入力する。

評価担当者は、たとえばP01の1試行目を次で開く。
既定ブラウザはChromeである。

```powershell
.\scripts\windows\start_phase_d_evaluation.ps1 -ParticipantNumber 1 -Sequence 1
```

画面上部の`Phase D A/B evaluation`で次を行う。

1. `Evaluator ID`と条件表示が正しいことを確認する。
2. `start trial`を押す。ここからシナリオと操作数の計測が始まる。
3. 約15秒後の異常発生以降、評価者自身に操作してもらう。
4. 回答入力後に`finish`を押す。
5. `CSV`と`JSON`を両方保存する。

画面左メニュー内の回答操作は操作数に含めず、地図、警告、機体選択、カメラ、レイアウトのクリックを操作数として記録する。
`incident_to_local_analysis_seconds`は異常発生から、正解確認前に評価者が`600m detail`を押すまでの実時間である。

## 結果の集約

全CSVを1ディレクトリへ集め、次を実行する。

```powershell
python hakoniwa-geo-viewer\tools\phase_d_aggregate.py <CSVディレクトリ> --output-dir Plan20260811\phase-d-results
```

生成物:

- `phase-d-summary.json`: 機械可読な集計と判定
- `phase-d-summary.md`: S社向け1ページ相当の結果要約
- `phase-d-comparison.svg`: Mapray／Leaflet比較グラフ

ブラウザ出力が利用できない場合の空テンプレートは`phase-d-evaluation-template.csv`にある。ただし手入力時も
`measurement_kind=actual-human-evaluation`、`estimated=false`とし、推定値は混ぜない。

## 成功基準

最低3名の両条件完了を前提に、次のいずれかを満たす。

- Maprayの地点正答率がLeafletより20ポイント以上高い。
- Maprayの異常発生から局所解析までの中央値がLeafletより25%以上短い。

さらに全試行の機体ID・インシデントID整合率80%以上を必須とする。
5km B3Dは未整備なので、結果は標準地図／DEM＋600m詳細地区というStage 1条件の参考値として扱う。

## 正解データの管理

正解データは`hakoniwa-geo-viewer/config/evaluation/phase-d-evaluation.json`に固定している。
評価者にはこのファイルを見せない。試行終了後のブラウザ出力には回答と正誤を保存するが、API Key、個人名、Cookieは保存しない。
