import Foundation
import Testing

@testable import Yamatabi

/// 日の出・日の入りの計算。
///
/// この計算は登山計画の起点です。ここが狂うと「家を出る時刻」まで全部狂い、
/// 日没後の行動につながります。公表値と照合して守ります。
struct SunCalculatorTests {

    /// 日本標準時のカレンダー。端末の設定に左右されないよう、テストでは固定します。
    private static let jst: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        jst.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    /// 「5:42」の形に直す。
    private static func hhmm(_ date: Date) -> String {
        let parts = jst.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// 計算した時刻と、公表値との差（分）。
    private static func minutes(between date: Date, and expected: String) -> Int {
        let parts = expected.split(separator: ":").compactMap { Int($0) }
        let actual = jst.dateComponents([.hour, .minute], from: date)
        let actualMinutes = (actual.hour ?? 0) * 60 + (actual.minute ?? 0)
        return abs(actualMinutes - (parts[0] * 60 + parts[1]))
    }

    /// 国立天文台の公表値との照合。
    ///
    /// 許容は±2分。アルゴリズム（NOAA の日の出方程式）の精度がこの程度のためです。
    @Test(arguments: Reference.all)
    func 公表値と2分以内で一致する(reference: Reference) throws {
        let times = try #require(
            SunCalculator.times(
                latitude: reference.latitude,
                longitude: reference.longitude,
                date: Self.date(reference.year, reference.month, reference.day),
                calendar: Self.jst
            ),
            "\(reference.name): 日の出・日の入りを計算できませんでした"
        )

        let sunriseGap = Self.minutes(between: times.sunrise, and: reference.sunrise)
        let sunsetGap = Self.minutes(between: times.sunset, and: reference.sunset)

        let sunriseMessage = """
            \(reference.name) の日の出: 計算 \(Self.hhmm(times.sunrise)) / \
            公表 \(reference.sunrise)（差 \(sunriseGap)分）
            """
        let sunsetMessage = """
            \(reference.name) の日の入り: 計算 \(Self.hhmm(times.sunset)) / \
            公表 \(reference.sunset)（差 \(sunsetGap)分）
            """

        #expect(sunriseGap <= 2, "\(sunriseMessage)")
        #expect(sunsetGap <= 2, "\(sunsetMessage)")
    }

    /// 照合に使う1件。国立天文台の公表値です。
    struct Reference: Sendable, CustomStringConvertible {
        let name: String
        let latitude: Double
        let longitude: Double
        let year: Int
        let month: Int
        let day: Int
        let sunrise: String
        let sunset: String

        var description: String { name }

        /// 札幌から那覇まで、夏至と冬至で確かめます。
        /// 緯度の幅と季節の幅の両端を押さえれば、その間は大きく外れません。
        static let all: [Reference] = [
            .init(name: "札幌・夏至", latitude: 43.0642, longitude: 141.3469,
                  year: 2026, month: 6, day: 21, sunrise: "3:55", sunset: "19:18"),
            .init(name: "札幌・冬至", latitude: 43.0642, longitude: 141.3469,
                  year: 2026, month: 12, day: 22, sunrise: "7:03", sunset: "16:03"),
            .init(name: "東京・夏至", latitude: 35.6895, longitude: 139.6917,
                  year: 2026, month: 6, day: 21, sunrise: "4:25", sunset: "19:00"),
            .init(name: "東京・冬至", latitude: 35.6895, longitude: 139.6917,
                  year: 2026, month: 12, day: 22, sunrise: "6:47", sunset: "16:32"),
            .init(name: "那覇・夏至", latitude: 26.2124, longitude: 127.6809,
                  year: 2026, month: 6, day: 21, sunrise: "5:38", sunset: "19:25"),
            .init(name: "那覇・冬至", latitude: 26.2124, longitude: 127.6809,
                  year: 2026, month: 12, day: 22, sunrise: "7:13", sunset: "17:43")
        ]
    }

    /// 標高が高いほど、日の出は早く、日の入りは遅くなる。
    ///
    /// 山の上では地平線が下に見えるためです。富士山頂では海面より10分近く遅くなるので、
    /// 登山の計画では無視できません。
    @Test func 標高が高いほど日が長くなる() throws {
        let day = Self.date(2026, 8, 1)
        let seaLevel = try #require(
            SunCalculator.times(
                latitude: 35.3606, longitude: 138.7274, elevation: 0,
                date: day, calendar: Self.jst
            )
        )
        let summit = try #require(
            SunCalculator.times(
                latitude: 35.3606, longitude: 138.7274, elevation: 3776,
                date: day, calendar: Self.jst
            )
        )

        let sunsetDelay = summit.sunset.timeIntervalSince(seaLevel.sunset) / 60
        let sunriseAdvance = seaLevel.sunrise.timeIntervalSince(summit.sunrise) / 60

        #expect(
            sunsetDelay > 7 && sunsetDelay < 13,
            "富士山頂の日の入りは海面より7〜13分遅いはず。実際は \(Int(sunsetDelay))分"
        )
        #expect(
            sunriseAdvance > 7 && sunriseAdvance < 13,
            "富士山頂の日の出は海面より7〜13分早いはず。実際は \(Int(sunriseAdvance))分"
        )
    }

    /// 日の出は必ず日の入りより前。当たり前のことだが、暦の計算は符号を間違えやすい。
    @Test func 日の出は日の入りより前にくる() throws {
        for month in 1...12 {
            let times = try #require(
                SunCalculator.times(
                    latitude: 35.3606, longitude: 138.7274,
                    date: Self.date(2026, month, 15), calendar: Self.jst
                ),
                "\(month)月の計算に失敗しました"
            )
            #expect(times.sunrise < times.sunset, "\(month)月: 日の出が日の入りより後になっています")
        }
    }
}
