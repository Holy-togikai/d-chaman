import Foundation

/// 山のデータ。アプリに同梱した `mountains.json` を読み込みます。
///
/// 出典: 国土地理院「日本の主な山岳標高」
/// https://www.gsi.go.jp/kihonjohochousa/kihonjohochousa41139.html
///
/// JSON は `Tools/convert_mountains.py` で、国土地理院が配布している GeoJSON から
/// 生成しています。データを更新するときは CSV ではなく **GeoJSON を使ってください**。
/// CSV 版は Shift_JIS で表現できない文字が `?` に置き換わっており、
/// 薬萊山・屛風岳・屛風山・朳差岳の4山が欠けた表記になります。
enum MountainData {

    /// 全1,059地点（1,003山＋副峰）。標高の高い順に並んでいます。
    static let all: [Mountain] = load()

    /// 日本百名山だけを抜き出したもの。
    static let hyakumeizan: [Mountain] = all.filter(\.isHyakumeizan)

    private static func load() -> [Mountain] {
        guard let url = Bundle.main.url(forResource: "mountains", withExtension: "json") else {
            assertionFailure("mountains.json がアプリに同梱されていません")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([Mountain].self, from: data)
        } catch {
            assertionFailure("mountains.json を読み込めませんでした: \(error)")
            return []
        }
    }
}
