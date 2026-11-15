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
- [ ] 山データを国土地理院「日本の主な山岳標高」（約1,000山）に差し替え
- [ ] オフライン地図（範囲指定でタイルを事前取得）
- [ ] バックグラウンド GPS による軌跡記録
- [ ] 記録の保存と振り返り（SwiftData）

## 技術構成

| 用途 | 採用 | 備考 |
|---|---|---|
| UI | SwiftUI | |
| 地図 | MapKit + `MKTileOverlay` | **暫定**。オフライン対応時に MapLibre Native へ移行予定 |
| 位置情報 | CoreLocation | |
| 永続化 | SwiftData | 未導入 |

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
└── Models/
    ├── Mountain.swift     山のデータ型
    └── MountainData.swift 山の初期データ（暫定・手書き）
```
