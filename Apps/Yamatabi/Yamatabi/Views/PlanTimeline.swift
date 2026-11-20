import SwiftUI

/// 山行の時刻を、上から順に縦の線でつないで見せる。
///
/// ホームに段ごとのタイルを並べていたときは、出発・到着・登山・下山のどれを押しても
/// 同じ計画画面に飛ぶうえ、絵が多くて読み取りにくい、という指摘を受けました。
/// 時刻は「一本の流れ」なので、一本の線で見せるほうが分かりやすいという判断です。
struct PlanTimeline: View {
    let plan: HikePlan
    let schedule: HikeSchedule

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                PlanTimelineRow(row: row, isLast: index == rows.count - 1)
            }
        }
    }

    private var rows: [PlanTimelineRow.Content] {
        let arrival = schedule.startHikingAt.addingTimeInterval(-schedule.preparationTime)
        return [departure, arrivalRow(arrival), hiking, rest, descent]
    }

    // MARK: - 各段

    private var departure: PlanTimelineRow.Content {
        guard let leave = schedule.leaveHomeAt else {
            // 車の時間が分からないまま出発時刻を出すと、間に合わない計画を信じてしまう。
            return .init(
                title: "出発",
                value: "--:--",
                caption: missingDepartureReason,
                tone: .missing
            )
        }
        var caption = plan.originName ?? ""
        if schedule.driveTime > 0 {
            caption += " ・ 車で\(TrackStatistics.hourMinuteText(schedule.driveTime))"
        }
        return .init(title: "出発", value: timeText(leave), caption: caption, tone: .normal)
    }

    private var missingDepartureReason: String {
        if plan.originName == nil { return "出発地を決めると出ます" }
        if plan.trailheadName == nil { return "登山口を決めると出ます" }
        return "車の時間をまだ計算できていません"
    }

    private func arrivalRow(_ arrival: Date) -> PlanTimelineRow.Content {
        let place = plan.trailheadName ?? "登山口は未定"
        let prep = TrackStatistics.hourMinuteText(schedule.preparationTime)
        return .init(
            title: "到着",
            value: timeText(arrival),
            caption: "\(place) ・ 準備\(prep)",
            tone: plan.trailheadName == nil ? .missing : .normal
        )
    }

    private var hiking: PlanTimelineRow.Content {
        guard plan.courseTimeSeconds > 0 else {
            return .init(
                title: "登山",
                value: timeText(schedule.startHikingAt),
                caption: "コースタイムが未入力です",
                tone: .missing
            )
        }
        return .init(
            title: "登山",
            value: timeText(schedule.startHikingAt),
            caption: "歩き出す ・ 往復\(TrackStatistics.hourMinuteText(schedule.courseTime))",
            tone: .normal
        )
    }

    /// 休憩だけは時刻ではなく長さを出す。
    ///
    /// どこで何時に休むかは、その日の天気と進み具合で変わり、当たりません。
    /// 当たらない時刻を混ぜると、当たる時刻まで信用されなくなります（docs/decisions/0002）。
    private var rest: PlanTimelineRow.Content {
        var caption = "行程の途中で取る合計"
        if plan.cookingTime > 0 {
            caption += " ・ うち調理\(TrackStatistics.hourMinuteText(plan.cookingTime))"
        }
        return .init(
            title: "休憩",
            value: TrackStatistics.hourMinuteText(schedule.restTime),
            caption: caption,
            tone: plan.cookingTime > schedule.restTime ? .warning : .normal
        )
    }

    private var descent: PlanTimelineRow.Content {
        let sunset = timeText(schedule.sunset)
        guard schedule.finishesBeforeSunset else {
            return .init(
                title: "下山",
                value: timeText(schedule.descentAt),
                caption: "日の入り（\(sunset)）を過ぎます",
                tone: .warning
            )
        }
        return .init(
            title: "下山",
            value: timeText(schedule.descentAt),
            caption: "見込み ・ 日の入り \(sunset)",
            tone: .normal
        )
    }

    /// 登る日より前の時刻には「前日」を付ける。夜中に家を出る計画で、日付を取り違えないように。
    private func timeText(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let isPreviousDay = Calendar.current.startOfDay(for: date)
            < Calendar.current.startOfDay(for: plan.date)
        return isPreviousDay ? "前日 \(time)" : time
    }
}

/// 時刻の縦並びの1段。
struct PlanTimelineRow: View {
    struct Content {
        enum Tone { case normal, missing, warning }

        let title: String
        let value: String
        let caption: String
        let tone: Tone
    }

    let row: Content
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // 点と、次の段へつなぐ線。
            VStack(spacing: 0) {
                Circle()
                    .fill(row.tone == .missing ? Color.secondary.opacity(0.4) : Color.brandGreen)
                    .frame(width: 14, height: 14)
                    .padding(.top, 5)
                if !isLast {
                    Rectangle()
                        .fill(Color.brandGreen.opacity(0.3))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.title)
                        .font(.headline)
                    Spacer()
                    Text(row.value)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(valueColor)
                }
                Text(row.caption)
                    .font(.caption)
                    .foregroundStyle(row.tone == .warning ? Color.orange : Color.secondary)
            }
            .padding(.bottom, isLast ? 0 : 18)
        }
        .accessibilityElement(children: .combine)
    }

    private var valueColor: Color {
        switch row.tone {
        case .normal: .primary
        case .missing: .secondary
        case .warning: .orange
        }
    }
}
