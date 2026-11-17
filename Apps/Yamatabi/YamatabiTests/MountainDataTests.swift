import Foundation
import Testing

@testable import Yamatabi

/// 同梱している山岳データと、その絞り込み。
///
/// データは `Tools/convert_mountains.py` が生成します。生成し直したときに
/// 壊れていないかを、ここで見張ります。
struct MountainDataTests {

    // MARK: - 件数

    /// 国土地理院「日本の主な山岳標高」の1,003山・1,059地点。
    /// 1つの山に複数の山頂があるため、地点数のほうが多くなります。
    @Test func 山岳データが1059地点ある() {
        #expect(
            MountainData.all.count == 1059,
            "地点数が変わりました。データを更新したなら README の記載も直してください。実際は \(MountainData.all.count)"
        )
    }

    @Test func 百名山は100座ちょうど() {
        #expect(
            MountainData.hyakumeizan.count == 100,
            "百名山は100座のはず。実際は \(MountainData.hyakumeizan.count)"
        )
    }

    /// 副峰を含めると145地点になる。これは正しい状態です。
    /// 「百名山だけ」の絞り込みでこちらを使うと、タブ間で件数が食い違います。
    @Test func 副峰を含めると145地点になる() {
        let withSubPeaks = MountainData.all.filter(\.isHyakumeizan)
        #expect(withSubPeaks.count == 145, "実際は \(withSubPeaks.count)")
    }

    // MARK: - 絞り込みの一致

    /// 「百名山」のタブと、検索タブの「日本百名山だけ」が同じ件数になること。
    ///
    /// 片方が代表の山頂だけ（100）、もう片方が副峰込み（145）を数えていて、
    /// 画面によって件数が違う不具合がありました。
    @Test func 検索の百名山だけと百名山タブの件数が一致する() {
        let searched = MountainData.search("", onlyHyakumeizan: true)
        #expect(
            searched.count == MountainData.hyakumeizan.count,
            "検索 \(searched.count)件 / 百名山タブ \(MountainData.hyakumeizan.count)座。一致するはず"
        )
        #expect(searched.count == 100)
    }

    @Test func 絞り込みを外すと全地点が出る() {
        #expect(MountainData.search("", onlyHyakumeizan: false).count == MountainData.all.count)
    }

    @Test func キーワードと百名山の絞り込みを併用できる() {
        let all富士 = MountainData.search("ふじ", onlyHyakumeizan: false)
        let 百名山富士 = MountainData.search("ふじ", onlyHyakumeizan: true)

        #expect(!all富士.isEmpty, "「ふじ」で何も出ないのはおかしい")
        #expect(百名山富士.count <= all富士.count, "絞り込むと件数は減るはず")
        let 代表だけ = 百名山富士.allSatisfy(\.isHyakumeizanPeak)
        #expect(代表だけ, "絞り込んだ結果に副峰が混ざっています")
    }

    @Test func 山名でもふりがなでも都道府県でも探せる() {
        #expect(!MountainData.search("富士山", onlyHyakumeizan: false).isEmpty, "山名")
        #expect(!MountainData.search("ふじさん", onlyHyakumeizan: false).isEmpty, "ふりがな")
        #expect(!MountainData.search("山梨県", onlyHyakumeizan: false).isEmpty, "都道府県")
    }

    // MARK: - データの整合

    @Test func 代表の山頂は必ず百名山でもある() {
        let 矛盾 = MountainData.all.filter { $0.isHyakumeizanPeak && !$0.isHyakumeizan }
        #expect(矛盾.isEmpty, "代表なのに百名山でない地点があります: \(矛盾.map(\.displayName))")
    }

    @Test func IDが重複していない() {
        let ids = MountainData.all.map(\.id)
        #expect(Set(ids).count == ids.count, "IDが重複しています")
    }

    /// 百名山の一覧に同じ名前が2つ並ばないこと。
    /// 「白根山」が日光と草津で2つ出ると、どちらか分かりません。
    @Test func 百名山の表示名が重複しない() {
        let names = MountainData.hyakumeizan.map(\.hyakumeizanDisplayName)
        let duplicates = Dictionary(grouping: names, by: { $0 }).filter { $0.value.count > 1 }
        #expect(duplicates.isEmpty, "同じ名前が複数あります: \(duplicates.keys.sorted())")
    }

    @Test func 緯度経度が日本の範囲に収まっている() {
        let 範囲外 = MountainData.all.filter {
            $0.latitude < 20 || $0.latitude > 46 || $0.longitude < 122 || $0.longitude > 154
        }
        #expect(範囲外.isEmpty, "日本の外にある地点: \(範囲外.map(\.displayName).prefix(5))")
    }

    @Test func 標高が正の値になっている() {
        let おかしい = MountainData.all.filter { $0.elevation <= 0 || $0.elevation > 3776 }
        #expect(おかしい.isEmpty, "標高がおかしい地点: \(おかしい.map(\.displayName).prefix(5))")
    }

    /// CSV ではなく GeoJSON から作っているか。
    /// CSV は Shift_JIS のため、この4山が `?` に化けます。
    @Test func 文字化けしやすい4山が正しく入っている() {
        for name in ["薬萊山", "屛風山", "朳差岳"] {
            #expect(
                MountainData.all.contains { $0.name.contains(name) },
                "\(name) が見つかりません。CSV から作っていませんか（README 参照）"
            )
        }
        #expect(
            MountainData.all.contains { $0.name.contains("屛風岳") || $0.peak?.contains("屛風岳") == true },
            "屛風岳 が見つかりません"
        )
        #expect(
            !MountainData.all.contains { $0.name.contains("?") },
            "山名に ? が入っています。Shift_JIS の CSV から作った疑いがあります"
        )
    }
}
