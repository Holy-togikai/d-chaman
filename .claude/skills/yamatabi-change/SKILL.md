---
name: yamatabi-change
description: 山旅アプリに変更を加えて出すまでの手順。コードを書く・画面を変える・不具合を直すときに使う。ビルド、シミュレータでの確認、証拠集め、コミット、PR までを一本で行う。
---

# 山旅アプリの変更手順

変更を一つ出すたびに、この順番でやってください。飛ばすと、このプロジェクトで
実際に起きた失敗（壊れた画面に気づかずマージ、古いビルドを見て判断）を繰り返します。

## 0. 始める前に

```bash
cd /Users/tobira2/Developer/d-chaman
git branch --show-current
git status --short
```

- main にいるなら、**必ずブランチを切る**。`git checkout -b feature/<短い英語>`
- 前回の未コミットが残っていたら、それが何かを確かめてから進む

## 1. 読む

- `tasks.json` の該当タスクの `passes` — これが合格条件です
- `docs/requirements.md` — 壊してはいけない約束
- `docs/voice.md` — 文言を書くなら必読

## 2. 書く

- コメントは日本語で、**なぜそうしたか**を書く
- 色は直接書かず `Color.brandGreen` / `Color.brandGreenDeep` を使う
- `.sheet` / `.alert` は `Form` / `List` の直下に置く

## 3. ビルドと静的検査

```bash
cd Apps/Yamatabi
xcodebuild -project Yamatabi.xcodeproj -scheme Yamatabi -configuration Debug \
  -destination "id=$(xcrun devicectl list devices 2>/dev/null | awk '/iPhone 17 /{print $3}' | head -1)" \
  build 2>&1 | grep -E "error:|BUILD"
/opt/homebrew/bin/swiftlint lint --quiet --config .swiftlint.yml
```

シミュレータの UDID は `xcrun simctl list devices booted` でも調べられます。
**両方とも通るまで次へ進まない。**

## 4. 画面で確かめる

ビルドが通っただけでは何も分かりません。**必ず動かしてください。**

```bash
xcrun simctl install <UDID> <アプリのパス>
xcrun simctl launch <UDID> jp.d-chaman.Yamatabi
```

そのうえで、
- 変えた画面の写真を撮る（`scale` は 0.3〜0.45）
- **触る**。ボタンを押し、遷移し、戻れることを確かめる
- 計算を変えたなら、**具体的な数値を読み取って書き留める**

## 5. 証拠をまとめる

`tasks.json` の `evidence` に書きます。「確認しました」では不足です。

```
富士宮口の計画で、日没基準: 家を出る 前日22:57 → 歩き出す 2:58 → 下山 15:46
（日の入り 16:46 の1時間前）。自由設定 6:00 では下山 18:48 となり、
間に合わない旨が赤で出ることを確認。画面写真2枚。
```

## 6. コミット

`docs/voice.md` の書式で。**なぜそうしたかを本文に書く。**

## 7. PR

```bash
gh pr create --base main --head <ブランチ> --title "<型>(Yamatabi): <日本語>" --body "..."
```

本文は `## 変更` / `## 確認したこと` / `## 補足` の3つ。
**できていないことを隠さない。**

## 8. 止まる

**PR を作ったら、そこで止まってください。**
マージは人間の承認が要ります（`docs/safety.md`）。

## 9. 記録する

`progress.md` に追記。ブランチ名・PR番号・次の一手を必ず書く。

## 実機に入れるとき

人間に頼まれたときだけ。

```bash
xcrun devicectl list devices | grep -i physical   # connected か確かめる
cd Apps/Yamatabi
xcodebuild -project Yamatabi.xcodeproj -scheme Yamatabi -configuration Debug \
  -destination 'id=<実機のUDID>' -allowProvisioningUpdates build 2>&1 | grep -E "error:|BUILD"
xcrun devicectl device install app --device <実機のUDID> \
  ~/Library/Developer/Xcode/DerivedData/Yamatabi-*/Build/Products/Debug-iphoneos/Yamatabi.app
xcrun devicectl device process launch --device <実機のUDID> jp.d-chaman.Yamatabi
```

端末がロックされていると起動だけ失敗します。その場合は**入ったが起動は未確認**と
正直に報告してください。
