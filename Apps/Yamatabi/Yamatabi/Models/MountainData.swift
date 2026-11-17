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

    /// 日本百名山の100座。1座につき代表の山頂を1つだけ含みます。
    /// 副峰を含めた145地点が必要な場合は `all.filter(\.isHyakumeizan)` を使ってください。
    static let hyakumeizan: [Mountain] = all.filter(\.isHyakumeizanPeak)

    /// キーワードで絞り込む。
    ///
    /// - Parameter onlyHyakumeizan: 日本百名山だけに限るか。
    ///   `hyakumeizan` と同じ100座になるよう、代表の山頂だけを通します。
    ///   `isHyakumeizan` で絞ると副峰（荒川岳の中岳など）まで入って145地点になり、
    ///   百名山のタブと件数が食い違います。
    static func search(
        _ query: String,
        onlyHyakumeizan: Bool,
        in mountains: [Mountain] = all
    ) -> [Mountain] {
        // データは標高の高い順に並んだ状態で読み込んでいるので、並べ替えは不要。
        mountains.filter { mountain in
            (!onlyHyakumeizan || mountain.isHyakumeizanPeak) && mountain.matches(query)
        }
    }

    /// IDから山を引く。登山記録に残したIDから山を復元するのに使います。
    static func mountain(id: String) -> Mountain? {
        byID[id]
    }

    private static let byID: [String: Mountain] = Dictionary(
        all.map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
    )

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
