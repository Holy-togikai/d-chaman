import Foundation
import Testing

@testable import Yamatabi

/// 同梱しているコースタイムのデータ。
///
/// この数字を信じて人が山に入ります。短く出ると日没後の行動につながるため、
/// 生成し直したときに壊れていないかを厳しく見ます。
struct CourseRouteDataTests {

    // MARK: - 収録の規模

    @Test func ルートが400件以上ある() {
        #expect(
            CourseRouteData.all.count >= 400,
            "収録が減っています。実際は \(CourseRouteData.all.count) 件"
        )
    }

    @Test func 対象の山が200座以上ある() {
        let mountains = Set(CourseRouteData.all.map(\.mountainID))
        #expect(mountains.count >= 200, "実際は \(mountains.count) 山")
    }

    /// グレーディングを公表している県が、すべて収録されていること。
    /// 片方の出どころだけを取り込むと、県がまるごと抜け落ちます。
    @Test func 公表している11の県と山域がそろっている() {
        let prefectures = Set(CourseRouteData.all.map(\.prefecture))
        for name in ["長野県", "山梨県", "新潟県", "富山県", "岐阜県", "静岡県",
                     "群馬県", "山形県", "栃木県", "秋田県", "石鎚山系"] {
            #expect(prefectures.contains(name), "\(name) のルートが1件もありません")
        }
    }

    // MARK: - 既知の値

    /// 富士山の富士宮口は、標高差からの概算（約7時間28分）と公表値が4時間以上違う、
    /// このアプリで最も重要な実例です。ここが変わったら、データを疑ってください。
    @Test func 富士宮口のコースタイムが11時間48分のまま() throws {
        let fuji = CourseRouteData.all.filter { $0.mountainName.contains("富士") }
        let fujinomiya = try #require(
            fuji.first { $0.route.contains("富士宮口") },
            "富士宮口のルートが見つかりません"
        )
        #expect(
            abs(fujinomiya.courseTime - (11 * 3600 + 48 * 60)) < 60,
            "11時間48分のはず。実際は \(TrackStatistics.hourMinuteText(fujinomiya.courseTime))"
        )
    }

    @Test func 富士山の5つの登山口がそろっている() {
        let fuji = CourseRouteData.all.filter { $0.mountainName.contains("富士") }
        for 登山口 in ["スバルライン", "富士宮口", "須走口", "馬返", "御殿場口"] {
            #expect(
                fuji.contains { $0.route.contains(登山口) },
                "\(登山口) のルートが見つかりません"
            )
        }
    }

    // MARK: - 値の妥当性

    @Test func コースタイムが現実的な範囲に収まっている() {
        let おかしい = CourseRouteData.all.filter {
            $0.courseTime <= 0 || $0.courseTime > 60 * 3600
        }
        #expect(おかしい.isEmpty, "コースタイムがおかしい: \(おかしい.map(\.route).prefix(5))")
    }

    @Test func ルート長が現実的な範囲に収まっている() {
        let おかしい = CourseRouteData.all.filter { $0.lengthKm <= 0 || $0.lengthKm > 200 }
        #expect(おかしい.isEmpty, "ルート長がおかしい: \(おかしい.map(\.route).prefix(5))")
    }

    @Test func 体力度は1から10まで() {
        let 範囲外 = CourseRouteData.all.filter { $0.fitnessLevel < 1 || $0.fitnessLevel > 10 }
        #expect(範囲外.isEmpty, "体力度が範囲外: \(範囲外.map(\.route).prefix(5))")
    }

    @Test func 難易度はAからEまで() {
        let 範囲外 = CourseRouteData.all.filter { !["A", "B", "C", "D", "E"].contains($0.difficultyLevel) }
        #expect(範囲外.isEmpty, "難易度が範囲外: \(範囲外.map(\.route).prefix(5))")
    }

    /// 登山口が山頂より高いことはない。列を読み違えると起きます。
    @Test func 登山口は山頂より低い() {
        let 逆転 = CourseRouteData.all.filter { route in
            guard let mountain = MountainData.mountain(id: route.mountainID) else { return false }
            return route.startElevation > Double(mountain.elevation)
        }
        #expect(逆転.isEmpty, "登山口が山頂より高い: \(逆転.map(\.route).prefix(5))")
    }

    /// 小屋から小屋への区間は入れない。
    ///
    /// 車で行けないうえ、登山口からの計画に使うとコースタイムを短く見積もってしまいます。
    @Test func 小屋から小屋への区間が入っていない() {
        let 区間 = CourseRouteData.all.filter { route in
            let hut = { (name: String) in
                ["小屋", "山荘", "ヒュッテ", "小舎"].contains { name.hasSuffix($0) }
            }
            return hut(route.startName) && hut(route.endName) && route.route.contains("→")
        }
        #expect(区間.isEmpty, "区間の評価が混ざっています: \(区間.map(\.route).prefix(5))")
    }

    // MARK: - 結びつき

    @Test func すべてのルートが実在する山に結びついている() {
        let 迷子 = CourseRouteData.all.filter { MountainData.mountain(id: $0.mountainID) == nil }
        #expect(迷子.isEmpty, "山に結びついていない: \(迷子.map(\.route).prefix(5))")
    }

    @Test func 往復のルートは出発地と終了地が同じ() {
        let 矛盾 = CourseRouteData.all.filter { $0.isRoundTrip && $0.startName != $0.endName }
        #expect(矛盾.isEmpty, "往復なのに終了地が違う: \(矛盾.map(\.route).prefix(5))")
    }

    @Test func 山ごとの取り出しが動く() throws {
        let fuji = try #require(
            MountainData.all.first { $0.name == "富士山" },
            "富士山が見つかりません"
        )
        #expect(!CourseRouteData.routes(for: fuji.id).isEmpty)
        #expect(CourseRouteData.routes(for: "存在しないID").isEmpty)
    }
}
