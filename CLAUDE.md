# CLAUDE.md

まず `AGENTS.md` を読んでください。この仕事の案内図です。
ここには Claude Code で作業するときだけの追加ルールを書いています。

## 作業の始め方

セッションを開いたら、黙って作業に入らず、次を声に出して確認してください。

1. `progress.md` の末尾 — 前回どこで終わったか
2. `tasks.json` — `status` が `in_progress` のものがあれば、それが続き
3. `git status` と `git branch --show-current` — 前回の未コミットが残っていないか

## 道具の使い分け

| やりたいこと | 使うもの |
|---|---|
| ビルド | `xcodebuild`（シミュレータ用・実機用はセクション下部） |
| 静的検査 | `swiftlint lint --quiet --config Apps/Yamatabi/.swiftlint.yml` |
| 画面の確認 | iOS Simulator の MCP ツール（`mcp__Claude_Code_iOS_Simulator__control`） |
| 実機への配置 | `xcrun devicectl` |
| PR | `gh`（`/opt/homebrew/bin/gh`） |
| データ生成 | `python3 Apps/Yamatabi/Tools/*.py` |

### ビルドの定型

```bash
cd Apps/Yamatabi && xcodebuild -project Yamatabi.xcodeproj -scheme Yamatabi \
  -configuration Debug -destination 'id=<シミュレータのUDID>' build 2>&1 | grep -E "error:|BUILD"
```

実機は `-destination 'id=<実機のUDID>' -allowProvisioningUpdates`。
UDID は `xcrun devicectl list devices` で調べます。

## Claude Code 特有の注意

- **シミュレータの画面写真は `scale` を 0.3〜0.45 にする。** 等倍だと読み取りの
  コストが高いだけで、得られる情報は変わりません。
- **1行の `swiftlint` と `xcodebuild` は必ず `grep` で絞る。** 全文を読む価値はありません。
- **ファイルを書き換えたら、読み返して確認しない。** Edit が失敗すればエラーが返ります。
- **シミュレータの UDID はセッションごとに変わりうる。** 決め打ちせず毎回調べる。
- **日本語入力はシミュレータでは打てない。** 日本語の検索などを確かめたいときは
  実機を使うか、確認を人間に頼んでください。

## 書いたコードについて

- コメントは**日本語**で、「何をしているか」ではなく**「なぜそうしたか」**を書く。
  詳しくは `docs/voice.md`。
- SwiftUI の `.sheet` / `.alert` は **`Form` や `List` の直下に付ける。**
  `Section` に付けると行ごとに複製され、画面遷移が壊れます（実際に起きた不具合です）。

## 終わり方

セッションを閉じる前に、必ず `progress.md` に追記してください。
書式は `progress.md` の冒頭にあります。**これを忘れると次のセッションが迷子になります。**
