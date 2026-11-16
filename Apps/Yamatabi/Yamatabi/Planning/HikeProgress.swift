import Foundation

/// 山行の流れ。出発から帰りの寄り道までを6つに分けています。
enum HikeStage: String, CaseIterable, Identifiable {
    case departure
    case arrival
    case hiking
    case meal
    case descent
    case detour

    var id: String { rawValue }

    var title: String {
        switch self {
        case .departure: "出発"
        case .arrival: "到着・準備"
        case .hiking: "登山"
        case .meal: "山ごはん"
        case .descent: "下山"
        case .detour: "帰路の寄り道"
        }
    }

    var symbolName: String {
        switch self {
        case .departure: "car.fill"
        case .arrival: "parkingsign.circle.fill"
        case .hiking: "figure.hiking"
        case .meal: "fork.knife"
        case .descent: "sunset.fill"
        case .detour: "drop.fill"
        }
    }
}

/// いま山行のどこにいるか。
///
/// 済んだかどうかを利用者に押させると、押し忘れたぶんだけ画面が嘘をつきます。
/// そのため、時計・記録の状態・計画の中身だけから機械的に決めています。
struct HikeProgress {
    /// 進行中のステージ。出発前や、時刻を計算できないときは nil。
    let current: HikeStage?
    /// すでに通り過ぎたステージ。
    let finished: Set<HikeStage>
    /// 家を出るまでの残り時間。出発後は nil。
    let timeUntilDeparture: TimeInterval?

    func state(of stage: HikeStage) -> State {
        if stage == current { return .current }
        if finished.contains(stage) { return .finished }
        return .upcoming
    }

    enum State {
        case finished
        case current
        case upcoming
    }

    /// 計画と時計から進み具合を割り出す。
    ///
    /// - Parameter isRecording: 記録中なら、時刻に関わらず登山中とみなします。
    ///   早着きして先に歩き出した場合に、画面が「到着・準備」のままになるのを防ぎます。
    static func make(
        for plan: HikePlan,
        schedule: HikeSchedule?,
        isRecording: Bool,
        now: Date = Date()
    ) -> HikeProgress {
        guard let schedule else {
            return HikeProgress(
                current: isRecording ? .hiking : nil,
                finished: [],
                timeUntilDeparture: nil
            )
        }

        // 山ごはんには時刻がありません（モデルに持っていないため）。
        // 時系列に並べるのは時刻のある4つだけで、山ごはんと寄り道は別に扱います。
        let arrival = schedule.leaveHomeAt.addingTimeInterval(schedule.driveTime)

        if isRecording {
            return HikeProgress(
                current: .hiking,
                finished: [.departure, .arrival],
                timeUntilDeparture: nil
            )
        }

        if now < schedule.leaveHomeAt {
            return HikeProgress(
                current: nil,
                finished: [],
                timeUntilDeparture: schedule.leaveHomeAt.timeIntervalSince(now)
            )
        }

        if now < arrival {
            return HikeProgress(current: .departure, finished: [], timeUntilDeparture: nil)
        }

        if now < schedule.startHikingAt {
            return HikeProgress(
                current: .arrival,
                finished: [.departure],
                timeUntilDeparture: nil
            )
        }

        if now < schedule.descentDeadline {
            return HikeProgress(
                current: .hiking,
                finished: [.departure, .arrival],
                timeUntilDeparture: nil
            )
        }

        return HikeProgress(
            current: .detour,
            finished: [.departure, .arrival, .hiking, .descent],
            timeUntilDeparture: nil
        )
    }
}
