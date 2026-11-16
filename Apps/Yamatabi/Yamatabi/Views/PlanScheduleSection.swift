import SwiftUI

/// 逆算した時間割を表示するセクション。
struct PlanScheduleSection: View {
    let plan: HikePlan

    var body: some View {
        if let schedule = plan.schedule(), plan.courseTimeSeconds > 0 {
            Section {
                row("日の出", schedule.sunrise, "sunrise.fill", .orange)
                row("日の入り", schedule.sunset, "sunset.fill", .orange)

                row("下山を終える", schedule.descentDeadline, "flag.checkered", .red)
                row("歩き出す", schedule.startHikingAt, "figure.hiking", .brandGreen)

                // 移動時間が分からないまま出発時刻を出すと、間に合わない計画を
                // 信じてしまう。危険な側に外すので、揃うまでは出さない。
                if plan.driveTimeSeconds != nil {
                    row("家を出る", schedule.leaveHomeAt, "car.fill", .blue, emphasized: true)
                } else {
                    Label(
                        "出発地と登山口を設定すると、家を出る時刻を計算します。",
                        systemImage: "car"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                if schedule.requiresNightDeparture {
                    Label(
                        "日の出前の出発になります。夜間の運転と、暗い中での行動に備えてください。",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            } header: {
                Text("この日の時間割")
            } footer: {
                Text(footerText(for: schedule))
            }
        } else {
            Section("この日の時間割") {
                Label(
                    "あと必要なもの: " + plan.missingPieces.joined(separator: "、"),
                    systemImage: "info.circle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func footerText(for schedule: HikeSchedule) -> String {
        "日の入りの1時間前（\(time(schedule.descentDeadline))）までに下山を終える計画です。"
            + "登山口での準備に30分を見込んでいます。"
    }

    /// 登山日より前の日か。
    private func isPreviousDay(_ date: Date) -> Bool {
        !Calendar.current.isDate(date, inSameDayAs: plan.date)
    }

    private func row(
        _ title: String,
        _ date: Date,
        _ symbol: String,
        _ color: Color,
        emphasized: Bool = false,
        prefix: String? = nil
    ) -> some View {
        HStack {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol).foregroundStyle(color)
            }
            Spacer()
            Text((prefix ?? "") + time(date))
                .monospacedDigit()
                .font(emphasized ? .title3.weight(.semibold) : .body)
                .foregroundStyle(emphasized ? color : .primary)
        }
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
