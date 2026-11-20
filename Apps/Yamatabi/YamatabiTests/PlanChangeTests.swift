import Foundation
import SwiftData
import Testing

@testable import Yamatabi

/// 計画の山を後から変える。
///
/// 実機レビューで「山を選ぶと、どこで山を変えればいいか分からない」という指摘を受け、
/// 計画画面から山を変えられるようにしました。そのとき何を消して何を残すかの約束です。
@MainActor
struct PlanChangeTests {

    /// 端末に残さない、テスト専用の保存先。計画は保存先に入れて扱います。
    private static let context: ModelContext = {
        // テスト専用の保存先が作れないのは環境の故障で、続けても意味がないため止める。
        // swiftlint:disable:next force_try
        let container = try! ModelContainer(
            for: HikePlan.self, HikeRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }()

    private static let fuji = Mountain(
        id: "test-fuji",
        name: "富士山",
        peak: "剣ヶ峯",
        kana: "ふじさん",
        elevation: 3776,
        prefectures: ["山梨県", "静岡県"],
        latitude: 35.3606,
        longitude: 138.7274,
        isHyakumeizan: true,
        hyakumeizanName: nil,
        isHyakumeizanPeak: true
    )

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    /// 登山口・コース・車の時間・出発地まで埋まった計画。
    private static func makePlan(on day: Date) -> HikePlan {
        let plan = HikePlan(mountain: fuji, date: day)
        plan.courseTimeSeconds = 6 * 3600
        plan.driveTimeSeconds = 3 * 3600
        plan.trailheadLatitude = 35.3600
        plan.trailheadLongitude = 138.7300
        plan.originLatitude = 34.9547
        plan.originLongitude = 137.1744
        context.insert(plan)
        return plan
    }

    private static let kita = Mountain(
        id: "test-kita",
        name: "北岳",
        peak: nil,
        kana: "きただけ",
        elevation: 3193,
        prefectures: ["山梨県"],
        latitude: 35.6743,
        longitude: 138.2388,
        isHyakumeizan: true,
        hyakumeizanName: nil,
        isHyakumeizanPeak: true
    )

    /// 山を変えたら、前の山の登山口・コース・車の時間は残さない。
    /// 残すと、前の山の登山口から新しい山へ登る時間割ができてしまいます。
    @Test func 山を変えると山ごとの値が消える() throws {
        let plan = Self.makePlan(on: Self.date(2026, 8, 8))
        plan.trailheadName = "富士宮口五合目"
        plan.routeName = "富士宮口"

        plan.change(to: Self.kita)

        #expect(plan.mountainID == "test-kita")
        #expect(plan.mountainName == "北岳")
        #expect(plan.summitElevation == 3193)
        #expect(plan.trailheadName == nil)
        #expect(plan.trailheadCoordinate == nil)
        #expect(plan.routeName == nil)
        #expect(plan.courseTimeSeconds == 0)
        #expect(plan.driveTimeSeconds == nil)
    }

    /// 日付と出発地は山に依らないので、山を変えても残す。
    @Test func 山を変えても日付と出発地は残る() throws {
        let day = Self.date(2026, 8, 8)
        let plan = Self.makePlan(on: day)
        plan.originName = "自宅"

        plan.change(to: Self.kita)

        #expect(plan.date == day)
        #expect(plan.originName == "自宅")
        #expect(plan.originCoordinate != nil)
    }

    /// 同じ山を選び直しただけなら、入れたものを消さない。
    @Test func 同じ山を選び直しても何も消えない() throws {
        let plan = Self.makePlan(on: Self.date(2026, 8, 8))
        plan.trailheadName = "富士宮口五合目"

        plan.change(to: Self.fuji)

        #expect(plan.trailheadName == "富士宮口五合目")
        #expect(plan.courseTimeSeconds == 6 * 3600)
    }
}
