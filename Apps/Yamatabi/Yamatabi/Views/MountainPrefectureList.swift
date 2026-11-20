import SwiftUI

// MARK: - 都道府県から探す

/// 都道府県を選んで、その中の山を標高の高い順に並べる。
///
/// 山の名前を知らないうちは検索できません。「近場の山」から探す入口として用意しています。
struct MountainPrefectureList: View {
    let mountains: [Mountain]
    let onSelect: (Mountain) -> Void

    /// 最初は東京都。登山者がいちばん多い地域の入口に合わせています。
    @State private var prefecture = "東京都"

    /// 北から順に並べる。五十音順だと、隣の県が離れてしまって探しにくいためです。
    static let prefectures = [
        "北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県",
        "茨城県", "栃木県", "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県",
        "新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県", "岐阜県",
        "静岡県", "愛知県", "三重県", "滋賀県", "京都府", "大阪府", "兵庫県",
        "奈良県", "和歌山県", "鳥取県", "島根県", "岡山県", "広島県", "山口県",
        "徳島県", "香川県", "愛媛県", "高知県", "福岡県", "佐賀県", "長崎県",
        "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県"
    ]

    private var results: [Mountain] {
        mountains
            .filter { $0.prefectures.contains(prefecture) }
            .sorted { $0.elevation > $1.elevation }
    }

    var body: some View {
        List {
            Section {
                Picker("都道府県", selection: $prefecture) {
                    ForEach(Self.prefectures, id: \.self) { Text($0).tag($0) }
                }
            }

            Section {
                ForEach(results) { mountain in
                    Button { onSelect(mountain) } label: { MountainRow(mountain: mountain) }
                        .tint(.primary)
                }
            } header: {
                Text("\(results.count) 座（標高の高い順）")
            }
        }
    }
}
