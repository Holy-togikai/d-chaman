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

/// 時間割の組み立て方。
///
/// 日の出・日の入りはあくまで目安として出し、何時に歩き出すかは利用者が決めます。
enum ScheduleBasis: String, Codable, CaseIterable, Identifiable {
    /// 入山時刻を自分で決める。日没までに下山できるかを確かめます。
    case free
    /// 日の出の X 時間後に歩き出す。
    case sunrise
    /// 日の入りの X 時間前に下山を終える。
    case sunset

    var id: String { rawValue }

    var label: String {
        switch self {
        case .free: "自由設定"
        case .sunrise: "日の出基準"
        case .sunset: "日没基準"
        }
    }
}

/// 組み立てた時間割。
struct HikeSchedule: Equatable {
    let basis: ScheduleBasis
    let sunrise: Date
    let sunset: Date
    /// 歩き出す時刻。
    let startHikingAt: Date
    /// ペースを反映した行動時間（歩いている時間）。
    let courseTime: TimeInterval
    /// 休憩の合計。
    let restTime: TimeInterval
    /// 下山を終える見込みの時刻。「ここまでに下りる」ではなく「このくらいに下りる」です。
    let descentAt: Date
    /// 家を出る時刻。出発地が未設定なら nil。
    let leaveHomeAt: Date?
    /// 運転時間。
    let driveTime: TimeInterval
    /// 登山口での準備時間。
    let preparationTime: TimeInterval

    /// 歩き出してから下りてくるまでの合計。
    var totalOnMountain: TimeInterval { courseTime + restTime }

    /// 日の入りまでの余裕。負なら日没に間に合いません。
    var marginBeforeSunset: TimeInterval {
        sunset.timeIntervalSince(descentAt)
    }

    /// 日没までに下山できるか。
    var finishesBeforeSunset: Bool { marginBeforeSunset >= 0 }

    /// この時間割の主役になる時刻。
    ///
    /// 出発地を決めていれば「家を出る時刻」、決めていなければ「歩き出す時刻」です。
    /// 利用者が実際に動き出す瞬間が、いちばん知りたい時刻だからです。
    var headline: (title: String, date: Date) {
        if let leaveHomeAt { return ("家を出る", leaveHomeAt) }
        return ("歩き出す", startHikingAt)
    }

    /// 主役の時刻が日の出より前か。夜間の行動になることを知らせるために使います。
    var startsBeforeSunrise: Bool {
        headline.date < sunrise
    }
}

enum HikePlanner {

    /// 日の入りの何分前までに下山を終えるか（日没基準の既定値）。
    /// 日没後の行動は道迷いと滑落の危険が跳ね上がるため、1時間の余裕を既定にしています。
    static let defaultSunsetMargin: TimeInterval = 60 * 60

    /// 日の出の何時間後に歩き出すか（日の出基準の既定値）。
    static let defaultSunriseOffset: TimeInterval = 60 * 60

    /// 休憩の合計の既定値。景色を見て、ごはんを作って、という時間です。
    static let defaultRestTime: TimeInterval = 60 * 60

    /// 登山口に着いてから歩き出すまでの準備時間（トイレ・支度・登山届）。
    static let defaultPreparationTime: TimeInterval = 30 * 60

    /// 時間割の組み立てに必要な入力。
    struct Input {
        let latitude: Double
        let longitude: Double
        /// 山頂の標高。日の出・日の入り時刻の補正に使います。
        let elevation: Double
        let date: Date
        /// ガイドブック等の標準コースタイム（往復）。
        let courseTime: TimeInterval
        /// 標準コースタイムに掛ける倍率。
        let pace: HikePace
        /// 自宅から登山口までの移動時間。出発地が未設定なら nil。
        let driveTime: TimeInterval?
        var basis: ScheduleBasis = .sunset
        /// 自由設定のときに歩き出す時刻（その日の0時からの分）。
        var startHikingMinutes: Int = 6 * 60
        var sunriseOffset: TimeInterval = HikePlanner.defaultSunriseOffset
        var sunsetMargin: TimeInterval = HikePlanner.defaultSunsetMargin
        var restTime: TimeInterval = HikePlanner.defaultRestTime
        var preparationTime: TimeInterval = HikePlanner.defaultPreparationTime
    }

    /// 選んだ基準で時間割を組み立てる。
    static func schedule(_ input: Input, calendar: Calendar = .current) -> HikeSchedule? {
        guard let sun = SunCalculator.times(
            latitude: input.latitude,
            longitude: input.longitude,
            elevation: input.elevation,
            date: input.date,
            calendar: calendar
        ) else { return nil }

        let moving = input.courseTime * input.pace.rawValue
        let onMountain = moving + input.restTime

        let startHiking: Date
        switch input.basis {
        case .free:
            let midnight = calendar.startOfDay(for: input.date)
            startHiking = midnight.addingTimeInterval(TimeInterval(input.startHikingMinutes) * 60)
        case .sunrise:
            startHiking = sun.sunrise.addingTimeInterval(input.sunriseOffset)
        case .sunset:
            // 日の入りの手前に余裕を取った時刻から、行動時間ぶんだけ巻き戻す。
            startHiking = sun.sunset
                .addingTimeInterval(-input.sunsetMargin)
                .addingTimeInterval(-onMountain)
        }

        let leaveHome = input.driveTime.map {
            startHiking.addingTimeInterval(-input.preparationTime - $0)
        }

        return HikeSchedule(
            basis: input.basis,
            sunrise: sun.sunrise,
            sunset: sun.sunset,
            startHikingAt: startHiking,
            courseTime: moving,
            restTime: input.restTime,
            descentAt: startHiking.addingTimeInterval(onMountain),
            leaveHomeAt: leaveHome,
            driveTime: input.driveTime ?? 0,
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
