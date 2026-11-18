import Foundation
import SwiftData
import Testing

@testable import Yamatabi

/// 計画の選び方と、山行の進み具合。
///
/// ホーム画面が「つぎの山行」として何を出すか、いまどの段にいるかを決める部分です。
@MainActor
struct HikePlanTests {

    private static let jst: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    /// 端末に残さない、テスト専用の保存先。
    private static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: HikePlan.self, HikeRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

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

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        jst.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// 計画を1つ作る。時間割が出るよう、コースタイムまで埋めます。
    private static func makePlan(
        in context: ModelContext,
        on day: Date,
        courseTime: TimeInterval = 6 * 3600,
        driveTime: TimeInterval? = 3 * 3600
    ) -> HikePlan {
        let plan = HikePlan(mountain: fuji, date: day)
        plan.courseTimeSeconds = courseTime
        plan.driveTimeSeconds = driveTime
        plan.trailheadLatitude = 35.3600
        plan.trailheadLongitude = 138.7300
        plan.originLatitude = 34.9547
        plan.originLongitude = 137.1744
        context.insert(plan)
        return plan
    }

    // MARK: - つぎの山行の選び方

    @Test func いちばん近い計画が選ばれる() throws {
        let context = try Self.makeContext()
        let 来週 = Self.makePlan(in: context, on: Self.date(2026, 8, 8))
        _ = Self.makePlan(in: context, on: Self.date(2026, 8, 20))
        let now = Self.date(2026, 8, 1)

        let next = HikePlan.next(from: try context.fetch(FetchDescriptor<HikePlan>()), now: now)
        #expect(next?.id == 来週.id, "日付が近いほうが選ばれるはず")
    }

    /// 日付ではなく「家を出る時刻」で選ぶ。
    ///
    /// 富士宮口のように前日の深夜に出発する計画があるため、日付で選ぶと
    /// もう車で走っている計画を「明日のこと」として扱ってしまいます。
    @Test func 家を出る時刻で選ぶので前日出発の計画を取りこぼさない() throws {
        let context = try Self.makeContext()
        // 11月の富士山は日が短く、12時間のコースだと前日の夜に出ることになります。
        // 実際にこの条件の計画で、日付による選び方の問題が見つかりました。
        let plan = Self.makePlan(
            in: context, on: Self.date(2026, 11, 23), courseTime: 12 * 3600, driveTime: 4 * 3600
        )
        let schedule = try #require(plan.schedule())
        let leaveHome = try #require(schedule.leaveHomeAt)

        #expect(
            !Self.jst.isDate(leaveHome, inSameDayAs: plan.date),
            "この条件では前日出発になるはず。前提が崩れたらテストを見直すこと"
        )
        #expect(
            abs(plan.departureReference.timeIntervalSince(leaveHome)) < 1,
            "選ぶ基準は家を出る時刻であるはず"
        )
    }

    /// 下山したらすぐ消えてしまうと、帰り道で寄り道を探せない。
    @Test func 下山後もしばらくはつぎの山行として残る() throws {
        let context = try Self.makeContext()
        let plan = Self.makePlan(in: context, on: Self.date(2026, 8, 1))
        let schedule = try #require(plan.schedule())

        // 下山の1時間後
        let justAfter = schedule.descentAt.addingTimeInterval(3600)
        let plans = try context.fetch(FetchDescriptor<HikePlan>())
        #expect(HikePlan.next(from: plans, now: justAfter)?.id == plan.id, "下山直後はまだ残る")

        // 下山の10時間後
        let longAfter = schedule.descentAt.addingTimeInterval(10 * 3600)
        #expect(HikePlan.next(from: plans, now: longAfter) == nil, "十分に時間が経てば外れる")
    }

    @Test func 計画が無ければnilを返す() {
        #expect(HikePlan.next(from: [], now: Self.date(2026, 8, 1)) == nil)
    }

    // MARK: - 足りないもの

    @Test func 足りない項目を数え上げる() throws {
        let context = try Self.makeContext()
        let plan = HikePlan(mountain: Self.fuji, date: Self.date(2026, 8, 1))
        context.insert(plan)

        #expect(plan.missingPieces == ["登山口", "出発地", "コースタイム"])

        plan.trailheadLatitude = 35.36
        plan.trailheadLongitude = 138.73
        #expect(plan.missingPieces == ["出発地", "コースタイム"])

        plan.originLatitude = 34.95
        plan.originLongitude = 137.17
        plan.courseTimeSeconds = 3600
        #expect(plan.missingPieces.isEmpty)
    }

    // MARK: - 進み具合

    @Test func 出発前は何の段にも入っていない() throws {
        let context = try Self.makeContext()
        let plan = Self.makePlan(in: context, on: Self.date(2026, 8, 10))
        let schedule = try #require(plan.schedule())
        let leaveHome = try #require(schedule.leaveHomeAt)

        let progress = HikeProgress.make(
            for: plan, schedule: schedule, isRecording: false,
            now: leaveHome.addingTimeInterval(-3600)
        )
        #expect(progress.current == nil)
        #expect(progress.finished.isEmpty)
        #expect(progress.timeUntilDeparture != nil, "出発までの残り時間が出るはず")
    }

    @Test func 移動中は出発の段にいる() throws {
        let context = try Self.makeContext()
        let plan = Self.makePlan(in: context, on: Self.date(2026, 8, 10))
        let schedule = try #require(plan.schedule())
        let leaveHome = try #require(schedule.leaveHomeAt)

        let progress = HikeProgress.make(
            for: plan, schedule: schedule, isRecording: false,
            now: leaveHome.addingTimeInterval(600)
        )
        #expect(progress.current == .departure)
        #expect(progress.timeUntilDeparture == nil, "もう出発しているので残り時間は出さない")
    }

    @Test func 歩き出したあとは登山の段にいる() throws {
        let context = try Self.makeContext()
        let plan = Self.makePlan(in: context, on: Self.date(2026, 8, 10))
        let schedule = try #require(plan.schedule())

        let progress = HikeProgress.make(
            for: plan, schedule: schedule, isRecording: false,
            now: schedule.startHikingAt.addingTimeInterval(3600)
        )
        #expect(progress.current == .hiking)
        #expect(progress.state(of: .departure) == .finished)
        #expect(progress.state(of: .arrival) == .finished)
        #expect(progress.state(of: .descent) == .upcoming)
    }

    /// 早く着いて先に歩き出した場合でも、記録中なら登山の段として扱う。
    /// 時刻だけで判断すると、画面が「到着・準備」のまま止まってしまいます。
    @Test func 記録中なら時刻によらず登山の段になる() throws {
        let context = try Self.makeContext()
        let plan = Self.makePlan(in: context, on: Self.date(2026, 8, 10))
        let schedule = try #require(plan.schedule())
        let leaveHome = try #require(schedule.leaveHomeAt)

        let progress = HikeProgress.make(
            for: plan, schedule: schedule, isRecording: true,
            now: leaveHome.addingTimeInterval(-7200)  // まだ家を出る前
        )
        #expect(progress.current == .hiking, "記録しているなら歩いているはず")
    }

    @Test func 下山後は寄り道の段になる() throws {
        let context = try Self.makeContext()
        let plan = Self.makePlan(in: context, on: Self.date(2026, 8, 10))
        let schedule = try #require(plan.schedule())

        let progress = HikeProgress.make(
            for: plan, schedule: schedule, isRecording: false,
            now: schedule.descentAt.addingTimeInterval(600)
        )
        #expect(progress.current == .detour)
        #expect(progress.state(of: .hiking) == .finished)
    }

    @Test func 時間割が出せなければ段を決めない() throws {
        let context = try Self.makeContext()
        let plan = HikePlan(mountain: Self.fuji, date: Self.date(2026, 8, 10))
        context.insert(plan)

        let progress = HikeProgress.make(for: plan, schedule: nil, isRecording: false)
        #expect(progress.current == nil)
        #expect(progress.timeUntilDeparture == nil)
    }

    // MARK: - 山ごはんの調理時間

    /// 食べる時刻は持たず、かかる時間だけを扱う（T-004 の判断）。
    @Test func レシピを選ばなければ調理時間はゼロ() throws {
        let context = try Self.makeContext()
        let plan = Self.makePlan(in: context, on: Self.date(2026, 8, 10))
        #expect(plan.cookingTime == 0)
    }

    /// バーナーは1台のことが多いので、2品なら順番に作る。だから足し算になる。
    @Test func 複数のレシピの調理時間は足される() throws {
        let context = try Self.makeContext()
        let plan = Self.makePlan(in: context, on: Self.date(2026, 8, 10))
        let two = Array(RecipeData.all.prefix(2))
        try #require(two.count == 2, "レシピが2品以上必要です")
        plan.recipes = two

        let expected = Double(two[0].cookingMinutes + two[1].cookingMinutes) * 60
        let message = """
            \(two[0].cookingMinutes)分＋\(two[1].cookingMinutes)分のはず。\
            実際は \(Int(plan.cookingTime / 60))分
            """
        #expect(plan.cookingTime == expected, "\(message)")
    }

    /// 人数を変えても調理時間は変わらない。量が増えても、作る手順は同じだから。
    @Test func 人数を変えても調理時間は変わらない() throws {
        let context = try Self.makeContext()
        let plan = Self.makePlan(in: context, on: Self.date(2026, 8, 10))
        plan.recipes = Array(RecipeData.all.prefix(2))
        let twoPeople = plan.cookingTime
        plan.mealServings = 4
        #expect(plan.cookingTime == twoPeople)
    }

    // MARK: - 高速料金の概算

    @Test func 高速料金の概算は50円単位で丸める() {
        let estimate = TollEstimate(highwayDistance: 100_000, vehicle: .standard)
        #expect(estimate.amount % 50 == 0, "50円単位のはず。実際は \(estimate.amount)")
        // 100km × 24.6 + 150 = 2,610 → ×1.1 = 2,871 → 2,850
        #expect(estimate.amount == 2850, "実際は \(estimate.amount)")
    }

    @Test func 車種で料金が変わる() {
        let kei = TollEstimate(highwayDistance: 100_000, vehicle: .kei).amount
        let standard = TollEstimate(highwayDistance: 100_000, vehicle: .standard).amount
        let medium = TollEstimate(highwayDistance: 100_000, vehicle: .medium).amount

        #expect(kei < standard, "軽自動車は普通車より安いはず")
        #expect(medium > standard, "中型車は普通車より高いはず")
    }

    @Test func 高速を使わなければ料金はゼロ() {
        #expect(TollEstimate(highwayDistance: 0).amount == 0)
    }

    /// 手で入れた金額は、概算と区別できるようにする。
    @Test func 手入力の金額は概算と区別される() {
        let manual = TollEstimate(manualAmount: 3080)
        #expect(manual.amount == 3080)
        #expect(manual.isManual)
        #expect(!TollEstimate(highwayDistance: 100_000).isManual)
    }
}
