import Foundation

/// 歩くペース。ガイドブックの標準コースタイムに対する倍率です。
enum HikePace: Double, CaseIterable, Identifiable, Codable {
    case fast = 0.8
    case standard = 1.0
    case slow = 1.2

    var id: Double { rawValue }

    var label: String {
        switch self {
        case .fast: "やや早い"
        case .standard: "標準"
        case .slow: "ややゆっくり"
        }
    }

    var detail: String {
        switch self {
        case .fast: "×0.8"
        case .standard: "×1.0"
        case .slow: "×1.2"
        }
    }
}

/// 逆算した計画。
struct HikeSchedule: Equatable {
    let sunrise: Date
    let sunset: Date
    /// 下山を終えていたい時刻（日の入りから余裕を引いた時刻）。
    let descentDeadline: Date
    /// ペースを反映した行動時間。
    let courseTime: TimeInterval
    /// 登山口を出発する時刻。
    let startHikingAt: Date
    /// 家を出る時刻。
    let leaveHomeAt: Date
    /// 運転時間。
    let driveTime: TimeInterval
    /// 登山口での準備時間。
    let preparationTime: TimeInterval

    /// 日の入りまでにどれだけ余裕があるか。
    var marginBeforeSunset: TimeInterval {
        sunset.timeIntervalSince(descentDeadline)
    }

    /// 出発が深夜や前日になっていないか。無理のある計画を知らせるために使います。
    var requiresNightDeparture: Bool {
        leaveHomeAt < sunrise
    }
}

enum HikePlanner {

    /// 日の入りの何分前までに下山を終えるか。
    /// 日没後の行動は道迷いと滑落の危険が跳ね上がるため、既定で1時間の余裕を取ります。
    static let defaultSunsetMargin: TimeInterval = 60 * 60

    /// 登山口に着いてから歩き出すまでの準備時間（トイレ・支度・登山届）。
    static let defaultPreparationTime: TimeInterval = 30 * 60

    /// 逆算に必要な入力。
    struct Input {
        let latitude: Double
        let longitude: Double
        /// 山頂の標高。日の入り時刻の補正に使います。
        let elevation: Double
        let date: Date
        /// ガイドブック等の標準コースタイム（往復）。
        let courseTime: TimeInterval
        /// 標準コースタイムに掛ける倍率。
        let pace: HikePace
        /// 自宅から登山口までの移動時間。
        let driveTime: TimeInterval
        var sunsetMargin: TimeInterval = HikePlanner.defaultSunsetMargin
        var preparationTime: TimeInterval = HikePlanner.defaultPreparationTime
    }

    /// 日の入りから逆算して、歩き出す時刻と家を出る時刻を求める。
    static func schedule(_ input: Input, calendar: Calendar = .current) -> HikeSchedule? {
        guard let sun = SunCalculator.times(
            latitude: input.latitude,
            longitude: input.longitude,
            elevation: input.elevation,
            date: input.date,
            calendar: calendar
        ) else { return nil }

        let adjustedCourseTime = input.courseTime * input.pace.rawValue
        let deadline = sun.sunset.addingTimeInterval(-input.sunsetMargin)
        let startHiking = deadline.addingTimeInterval(-adjustedCourseTime)
        let leaveHome = startHiking.addingTimeInterval(-input.preparationTime - input.driveTime)

        return HikeSchedule(
            sunrise: sun.sunrise,
            sunset: sun.sunset,
            descentDeadline: deadline,
            courseTime: adjustedCourseTime,
            startHikingAt: startHiking,
            leaveHomeAt: leaveHome,
            driveTime: input.driveTime,
            preparationTime: input.preparationTime
        )
    }

    /// 標高差からコースタイムをざっくり見積もる（往復）。
    ///
    /// ガイドブックの値が分からないときの当て推量です。
    /// 登りは標高差300m/時、下りは500m/時という、登山で広く使われる目安を用います。
    /// **水平距離を考慮していない**ため、なだらかに長く歩く山では短く出がちです。
    /// あくまで入力の初期値であり、分かるならガイドブックの値を使ってください。
    static func estimatedCourseTime(elevationGain: Double) -> TimeInterval {
        guard elevationGain > 0 else { return 0 }
        let ascent = elevationGain / 300.0 * 3600
        let descent = elevationGain / 500.0 * 3600
        return ascent + descent
    }
}
