import Foundation
import Testing

@testable import Yamatabi

/// 時間割の組み立て。
///
/// 3つの決め方（自由設定・日の出基準・日没基準）が、それぞれ意図どおりに
/// 時刻を出すかを見ます。ここが狂うと、間に合わない計画を利用者が信じてしまいます。
struct HikePlannerTests {

    private static let jst: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    /// 富士山（剣ヶ峯）。実際のアプリで使っている値です。
    private static let fujiLatitude = 35.3606
    private static let fujiLongitude = 138.7274
    private static let fujiElevation = 3776.0

    /// 2026年8月1日。
    private static var day: Date {
        jst.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12))!
    }

    /// 基本の入力。各テストで必要な部分だけ差し替えます。
    private static func input(
        basis: ScheduleBasis,
        courseTime: TimeInterval = 6 * 3600,
        pace: HikePace = .standard,
        driveTime: TimeInterval? = 2 * 3600,
        restTime: TimeInterval = 3600,
        startHikingMinutes: Int = 6 * 60,
        sunriseOffset: TimeInterval = 3600,
        sunsetMargin: TimeInterval = 3600
    ) -> HikePlanner.Input {
        HikePlanner.Input(
            latitude: fujiLatitude,
            longitude: fujiLongitude,
            elevation: fujiElevation,
            date: day,
            courseTime: courseTime,
            pace: pace,
            driveTime: driveTime,
            basis: basis,
            startHikingMinutes: startHikingMinutes,
            sunriseOffset: sunriseOffset,
            sunsetMargin: sunsetMargin,
            restTime: restTime
        )
    }

    // MARK: - 日没基準

    @Test func 日没基準では日の入りの指定時間前に下山する() throws {
        let schedule = try #require(
            HikePlanner.schedule(Self.input(basis: .sunset, sunsetMargin: 3600), calendar: Self.jst)
        )
        let gap = schedule.sunset.timeIntervalSince(schedule.descentAt)
        #expect(
            abs(gap - 3600) < 1,
            "日の入りの1時間前に下山するはず。実際の差は \(Int(gap / 60))分"
        )
        #expect(schedule.finishesBeforeSunset)
    }

    @Test func 日没基準で余裕を広げると歩き出しが早くなる() throws {
        let oneHour = try #require(
            HikePlanner.schedule(Self.input(basis: .sunset, sunsetMargin: 3600), calendar: Self.jst)
        )
        let twoHours = try #require(
            HikePlanner.schedule(
                Self.input(basis: .sunset, sunsetMargin: 2 * 3600), calendar: Self.jst
            )
        )
        let diff = oneHour.startHikingAt.timeIntervalSince(twoHours.startHikingAt)
        #expect(abs(diff - 3600) < 1, "余裕を1時間増やすと、歩き出しは1時間早まるはず")
    }

    // MARK: - 日の出基準

    @Test func 日の出基準では日の出の指定時間後に歩き出す() throws {
        let schedule = try #require(
            HikePlanner.schedule(Self.input(basis: .sunrise, sunriseOffset: 3600), calendar: Self.jst)
        )
        let gap = schedule.startHikingAt.timeIntervalSince(schedule.sunrise)
        #expect(
            abs(gap - 3600) < 1,
            "日の出の1時間後に歩き出すはず。実際の差は \(Int(gap / 60))分"
        )
    }

    /// 歩くのが遅い計画では、日没に間に合わないことを検知できる。
    ///
    /// これが働かないと、日没後の下山という最も危ない事態を見逃します。
    @Test func 日の出基準で行動時間が長いと日没に間に合わないと分かる() throws {
        let schedule = try #require(
            HikePlanner.schedule(
                Self.input(basis: .sunrise, courseTime: 14 * 3600), calendar: Self.jst
            )
        )
        #expect(!schedule.finishesBeforeSunset, "14時間のコースは日没に間に合わないはず")
        #expect(schedule.marginBeforeSunset < 0, "間に合わないときの余裕は負の値になるはず")
    }

    // MARK: - 自由設定

    @Test func 自由設定では決めた時刻に歩き出す() throws {
        let schedule = try #require(
            HikePlanner.schedule(
                Self.input(basis: .free, startHikingMinutes: 5 * 60 + 30), calendar: Self.jst
            )
        )
        let parts = Self.jst.dateComponents([.hour, .minute], from: schedule.startHikingAt)
        #expect(parts.hour == 5 && parts.minute == 30, "5:30 に歩き出すはず")
    }

    @Test func 自由設定では下山時刻が歩き出しと行動時間の合計になる() throws {
        let schedule = try #require(
            HikePlanner.schedule(
                Self.input(basis: .free, courseTime: 6 * 3600, restTime: 3600), calendar: Self.jst
            )
        )
        let onMountain = schedule.descentAt.timeIntervalSince(schedule.startHikingAt)
        #expect(
            abs(onMountain - 7 * 3600) < 1,
            "歩く6時間＋休憩1時間＝7時間のはず。実際は \(Int(onMountain / 3600))時間"
        )
    }

    // MARK: - 共通の性質

    /// 休憩を足したぶんだけ、下山が遅くなる。
    @Test func 休憩を増やすと下山が遅くなる() throws {
        let noRest = try #require(
            HikePlanner.schedule(Self.input(basis: .free, restTime: 0), calendar: Self.jst)
        )
        let twoHours = try #require(
            HikePlanner.schedule(Self.input(basis: .free, restTime: 2 * 3600), calendar: Self.jst)
        )
        let diff = twoHours.descentAt.timeIntervalSince(noRest.descentAt)
        #expect(abs(diff - 2 * 3600) < 1, "休憩2時間ぶん、下山が遅くなるはず")
    }

    /// ペースの倍率が行動時間に掛かる。
    @Test func ゆっくり歩くと行動時間が伸びる() throws {
        let standard = try #require(
            HikePlanner.schedule(
                Self.input(basis: .free, courseTime: 10 * 3600, pace: .standard), calendar: Self.jst
            )
        )
        let slow = try #require(
            HikePlanner.schedule(
                Self.input(basis: .free, courseTime: 10 * 3600, pace: .slow), calendar: Self.jst
            )
        )
        #expect(abs(standard.courseTime - 10 * 3600) < 1)
        #expect(abs(slow.courseTime - 12 * 3600) < 1, "×1.2 で12時間になるはず")
    }

    /// 出発地が無いときは「家を出る時刻」を出さない。
    ///
    /// 移動時間が分からないまま出発時刻を出すと、間に合わない計画を信じてしまいます。
    /// 危険な側に外れるので、揃うまでは出さないという約束です。
    @Test func 出発地が無いと家を出る時刻を出さない() throws {
        let schedule = try #require(
            HikePlanner.schedule(Self.input(basis: .sunset, driveTime: nil), calendar: Self.jst)
        )
        #expect(schedule.leaveHomeAt == nil, "移動時間が無いのに家を出る時刻を出してはいけない")
        #expect(schedule.headline.title == "歩き出す", "主役は歩き出す時刻になるはず")
    }

    @Test func 出発地があると家を出る時刻が主役になる() throws {
        let schedule = try #require(
            HikePlanner.schedule(
                Self.input(basis: .sunset, driveTime: 2 * 3600), calendar: Self.jst
            )
        )
        let leaveHome = try #require(schedule.leaveHomeAt)
        #expect(schedule.headline.title == "家を出る")

        // 家を出る → 移動2時間 → 準備30分 → 歩き出す
        let gap = schedule.startHikingAt.timeIntervalSince(leaveHome)
        let expected = 2 * 3600 + HikePlanner.defaultPreparationTime
        #expect(
            abs(gap - expected) < 1,
            "移動2時間＋準備30分＝2時間30分のはず。実際は \(Int(gap / 60))分"
        )
    }

    // MARK: - コースタイムの概算

    /// 標高差からの概算が、実際の公表値より短く出ることを記録として残す。
    ///
    /// これは不具合ではなく、水平距離を見ていないことによる既知の限界です。
    /// 「概算のほうが長い」という逆転が起きたら、計算を壊したということなので気づけます。
    @Test func 標高差からの概算は公表コースタイムより短い() {
        // 富士宮口の標高差1,398m に対する概算
        let estimated = HikePlanner.estimatedCourseTime(elevationGain: 1398)
        let published: TimeInterval = 11 * 3600 + 48 * 60  // 公表の標準コースタイム 11時間48分

        #expect(estimated < published, "概算は公表値より短く出るという既知の限界")
        #expect(
            estimated > 7 * 3600 && estimated < 8 * 3600,
            "概算は7〜8時間になるはず。実際は \(String(format: "%.1f", estimated / 3600))時間"
        )
    }

    @Test func 標高差がゼロならコースタイムもゼロ() {
        #expect(HikePlanner.estimatedCourseTime(elevationGain: 0) == 0)
        #expect(HikePlanner.estimatedCourseTime(elevationGain: -100) == 0)
    }
}
