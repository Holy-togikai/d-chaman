# 山旅（Yamatabi）

登山の「出発から帰宅まで」を一本でサポートする iOS アプリ。

## 目指しているもの

| Phase | 内容 | 状態 |
|---|---|---|
| **1** | 日本地図から山を選ぶ → オフライン地図 → GPS で登山記録 | 🚧 着手中 |
| 2 | 出発時刻の提案（自宅・交通手段・日の出時刻・コースタイム） | 未着手 |
| 3 | 下山後のおすすめ（地元レストラン・銭湯・温泉） | 未着手 |
| 4 | 山ごはん（レシピ提案・買い出しリスト生成） | 未着手 |
| 5 | App Store 公開・課金（StoreKit 2） | 未着手 |

## Phase 1 の進捗

- [x] Xcode プロジェクト作成（SwiftUI / iOS 17+）
- [x] 地理院タイルの地図表示（標準地図・淡色地図・写真を切替）
- [x] 山の一覧と検索（山名・ふりがな・都道府県）
- [x] 地図上のピン表示と、選択した山へのズーム
- [x] バックグラウンド GPS による軌跡記録（一時停止・再開つき）
- [x] 距離・累積標高・経過時間の算出と、記録中のライブ表示
- [x] 記録の保存と一覧・詳細表示（SwiftData）
- [x] 山データを国土地理院「日本の主な山岳標高」に差し替え（1,059地点）
- [x] 日本百名山の絞り込みと、地図上でのまとめ表示（クラスタリング）
- [ ] オフライン地図（範囲指定でタイルを事前取得）

## 技術構成

| 用途 | 採用 | 備考 |
|---|---|---|
| UI | SwiftUI | |
| 地図 | MapKit + `MKTileOverlay` | **暫定**。オフライン対応時に MapLibre Native へ移行予定 |
| 位置情報 | CoreLocation | バックグラウンド測位。`UIBackgroundModes` に `location` が必須 |
| 永続化 | SwiftData | 軌跡は JSON にして1レコードへ格納（点ごとのレコードにはしない） |

### 地図を MapLibre に移行する理由

MapKit は独自タイルの**オフライン保存を実質サポートしていない**ため、Phase 1 のオフライン対応の時点で
MapLibre Native へ移行します。現在はオンライン表示のみなので MapKit で足りています。

## ⚠️ 地図データのライセンス

地理院タイルは、**リアルタイムに読み込んで表示する場合は出典の明示のみで申請不要**で利用できます。
本アプリは画面左下に「地理院タイル」の出典表示を入れています（`ContentView.attribution`）。**消さないでください。**

一方、**端末内に保存するオフライン機能は「リアルタイム読み込み」に当たりません。**
標準地図などは基本測量成果であり、測量法に基づく申請が必要になる可能性があります。
オフライン機能の実装前に、国土地理院への申請可否を確認すること。

- 地理院タイル一覧・利用条件: https://maps.gsi.go.jp/development/ichiran.html

## ビルド方法

```bash
xcodebuild -project Yamatabi.xcodeproj -scheme Yamatabi \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Xcode で開く場合は `Yamatabi.xcodeproj` をダブルクリック。

## ディレクトリ構成

```
Yamatabi/
├── YamatabiApp.swift      アプリの入口
├── ContentView.swift      メイン画面（地図 + 山の検索）
├── Map/
│   ├── GSITile.swift      地理院タイルの種類と配信URL
│   └── GSIMapView.swift   MKMapView の SwiftUI ラッパー
├── Models/
│   ├── Mountain.swift     山のデータ型
│   └── MountainData.swift mountains.json の読み込み
└── Resources/
    └── mountains.json     山岳データ（生成物・直接編集しない）

Tools/
└── convert_mountains.py   国土地理院 GeoJSON → mountains.json の変換
```

## 山岳データについて

出典は国土地理院「日本の主な山岳標高」。**1,003山・1,059地点**（蔵王山の熊野岳・刈田岳のように、
1つの山に複数の山頂があるため地点数の方が多い）。

### データを更新する手順

```bash
curl -O https://www.gsi.go.jp/KOKUJYOHO/MOUNTAIN/1003zan20260331.zip
unzip 1003zan20260331.zip
python3 Tools/convert_mountains.py 1003zan20260331.geojson Yamatabi/Resources/mountains.json
```

### ⚠️ CSV ではなく GeoJSON を使うこと

国土地理院は CSV と GeoJSON の両方を配布していますが、**CSV は Shift_JIS のため
一部の文字が `?` に化けています**。具体的には次の4山が壊れます。

| 正しい表記 | CSV での表記 |
|---|---|
| 薬萊山 | 薬?山 |
| 蔵王山＜屛風岳＞ | 蔵王山＜?風岳＞ |
| 屛風山 | ?風山 |
| 朳差岳 | ?差岳 |

GeoJSON は UTF-8 で、これらが正しく入っています。

### 日本百名山のフラグについて

国土地理院のデータに百名山の情報は無いため、`convert_mountains.py` が山名で突き合わせて
付けています。地理院側の表記が深田久弥の呼称と異なるものがあるため、以下を手当てしています。

- **別名**: 五竜岳→五龍岳、九重山→くじゅう連山、穂高岳→奥穂高岳 など
- **同名の山の区別**: 「駒ヶ岳」は会津・越後・木曽・甲斐がすべて同じ山名で登録されているため、
  標高で特定している。「白根山」も日光（2,578m）と草津（2,160m）が同名
- **別の索引番号に分かれているもの**: 荒川岳の最高峰「東岳（悪沢岳）」は
  「荒川岳」とは別の索引番号で登録されている

現在 100座すべてを照合できています（副峰を含めて145地点にフラグが付く）。

## GPS記録の設計メモ

登山は行動時間が長いため、電池持ちと記録の確実性を最優先にしています。

| 設定 | 値 | 理由 |
|---|---|---|
| `desiredAccuracy` | `kCLLocationAccuracyBest` | `BestForNavigation` は車載ナビ向けで、常時フル稼働して電池を激しく消費する |
| `distanceFilter` | 5m | 時間間隔ではなく移動量で通知。立ち止まっている間は通知が来ない |
| `activityType` | `.fitness` | 徒歩での利用だと OS に伝える |
| `pausesLocationUpdatesAutomatically` | **false** | true だと iOS が勝手に測位を止め、休憩後に記録が再開されない。登山では致命的 |
| 権限 | 「App の使用中のみ」 | 「常に許可」は不要。バックグラウンド位置更新と併用すれば画面を消しても記録が続く |

### 精度に関する処理

- 水平精度 50m より悪い点、起動直後のキャッシュ位置（10秒以上前）は捨てる
- 累積標高は、基準点から 3m を超えて動いたときだけ加算するヒステリシス方式。
  GPS の標高は静止中でも数メートル揺れるため、素直に足すと実際の数倍になる

### シミュレータでの制約

`xcrun simctl location` は標高を与えないため、**シミュレータでは「のぼり」「標高」が常に 0／— になります。**
この2項目の検証は実機でしかできません。
