import SwiftUI

/// この日の時間割。
///
/// 時刻を決めるのは利用者です。日の出と日の入りは、その判断の材料として出しています。
struct PlanScheduleSection: View {
    @Bindable var plan: HikePlan

    var body: some View {
        basisSection
        if let schedule = plan.schedule(), plan.courseTimeSeconds > 0 {
            resultSection(schedule)
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

    // MARK: - 決め方

    private var basisSection: some View {
        Section {
            Picker("決め方", selection: $plan.scheduleBasis) {
                ForEach(ScheduleBasis.allCases) { basis in
                    Text(basis.label).tag(basis)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

            basisControl

            Stepper(value: $plan.restTime, in: 0...(4 * 3600), step: 15 * 60) {
                LabeledContent("休憩の合計", value: duration(plan.restTime))
            }
        } header: {
            Text("時間の決め方")
        } footer: {
            Text(basisFooter)
        }
    }

    @ViewBuilder
    private var basisControl: some View {
        switch plan.scheduleBasis {
        case .free:
            DatePicker(
                "歩き出す時刻",
                selection: startHikingBinding,
                displayedComponents: .hourAndMinute
            )
        case .sunrise:
            Stepper(value: $plan.sunriseOffset, in: 0...(6 * 3600), step: 15 * 60) {
                LabeledContent("日の出の何時間後に歩き出すか", value: duration(plan.sunriseOffset))
            }
        case .sunset:
            Stepper(value: $plan.sunsetMargin, in: 0...(6 * 3600), step: 15 * 60) {
                LabeledContent("日の入りの何時間前に下山するか", value: duration(plan.sunsetMargin))
            }
        }
    }

    private var basisFooter: String {
        switch plan.scheduleBasis {
        case .free:
            "決めた時刻に歩き出すと、日の入りまでに下山できるかを確かめます。"
        case .sunrise:
            "日の出のあとに歩き出す時刻を決めて、そこから家を出る時刻を逆算します。"
        case .sunset:
            "日の入りの手前に下山を終える時刻を決めて、そこから家を出る時刻を逆算します。"
        }
    }

    /// 自由設定の時刻。登る日の0時からの分として持っているものを Date に直します。
    private var startHikingBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.startOfDay(for: plan.date)
                    .addingTimeInterval(TimeInterval(plan.startHikingMinutes) * 60)
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                plan.startHikingMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    // MARK: - 結果

    @ViewBuilder
    private func resultSection(_ schedule: HikeSchedule) -> some View {
        Section {
            headlineRow(schedule)

            if schedule.leaveHomeAt == nil {
                Label(
                    "出発地と登山口を設定すると、家を出る時刻も計算します。",
                    systemImage: "car"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("この日の時間割")
        }

        Section {
            if schedule.leaveHomeAt != nil {
                row("歩き出す", schedule.startHikingAt, "figure.hiking", .brandGreen)
            }
            row("下山する見込み", schedule.descentAt, "flag.checkered", .brandGreen)
            row("日の出", schedule.sunrise, "sunrise.fill", .orange)
            row("日の入り", schedule.sunset, "sunset.fill", .orange)
        } footer: {
            Text(breakdown(schedule))
        }

        Section {
            sunsetVerdict(schedule)
            cookingNote(schedule)
            if schedule.startsBeforeSunrise {
                Label(
                    "\(schedule.headline.title)のは日の出前です。"
                        + "暗い中での運転と行動に備えてください。",
                    systemImage: "moon.stars.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
    }

    /// 主役の時刻。出発地があれば「家を出る」、なければ「歩き出す」。
    private func headlineRow(_ schedule: HikeSchedule) -> some View {
        let headline = schedule.headline
        return HStack {
            Label {
                Text(headline.title)
            } icon: {
                Image(systemName: schedule.leaveHomeAt == nil ? "figure.hiking" : "car.fill")
                    .foregroundStyle(Color.brandGreen)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(time(headline.date))
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.brandGreen)
                if isPreviousDay(headline.date) {
                    Text("前日").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 日没に間に合うか。自由設定では、これが知りたいことそのものです。
    private func sunsetVerdict(_ schedule: HikeSchedule) -> some View {
        let margin = schedule.marginBeforeSunset
        if schedule.finishesBeforeSunset {
            let text = "日の入りの\(duration(margin))前（\(time(schedule.descentAt))）に下山する見込みです。"
            return Label(text, systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(margin < 30 * 60 ? Color.orange : Color.brandGreen)
        }
        // 「2時間2分間に合いません」と読めてしまうため、「過ぎます」で言い切る。
        let text = "下山が日の入り（\(time(schedule.sunset))）を\(duration(-margin))過ぎます。"
            + "歩き出しを早めるか、コースを短くしてください。"
        return Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
    }

    /// 山ごはんの調理時間と、休憩の合計との関係。
    ///
    /// 調理のぶんは休憩の中に含まれます。2品で45〜50分かかるので、
    /// 休憩の既定（1時間）だと、ほとんどが調理で埋まります。
    /// 超えていれば下山が遅れるので、知らせます。
    @ViewBuilder
    private func cookingNote(_ schedule: HikeSchedule) -> some View {
        let cooking = plan.cookingTime
        if cooking > 0 {
            if cooking > schedule.restTime {
                Label(
                    "山ごはんの調理に\(duration(cooking))かかります。"
                        + "休憩の合計（\(duration(schedule.restTime))）を超えるので、"
                        + "そのぶん下山が遅くなります。",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            } else {
                Label(
                    "山ごはんの調理に\(duration(cooking))。"
                        + "休憩の合計（\(duration(schedule.restTime))）に収まっています。",
                    systemImage: "fork.knife"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func breakdown(_ schedule: HikeSchedule) -> String {
        var parts = ["歩く \(duration(schedule.courseTime))", "休憩 \(duration(schedule.restTime))"]
        if schedule.leaveHomeAt != nil {
            parts.insert("移動 \(duration(schedule.driveTime))", at: 0)
            parts.insert("登山口での準備 \(duration(schedule.preparationTime))", at: 1)
        }
        return parts.joined(separator: " ・ ")
    }

    // MARK: - 部品

    /// 登山日より前の日か。
    private func isPreviousDay(_ date: Date) -> Bool {
        !Calendar.current.isDate(date, inSameDayAs: plan.date)
    }

    private func row(_ title: String, _ date: Date, _ symbol: String, _ color: Color) -> some View {
        HStack {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol).foregroundStyle(color)
            }
            Spacer()
            Text((isPreviousDay(date) ? "前日 " : "") + time(date))
                .monospacedDigit()
        }
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// 「1時間30分」「45分」。
    private func duration(_ interval: TimeInterval) -> String {
        let minutes = Int((interval / 60).rounded())
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)分" }
        if rest == 0 { return "\(hours)時間" }
        return "\(hours)時間\(rest)分"
    }
}
