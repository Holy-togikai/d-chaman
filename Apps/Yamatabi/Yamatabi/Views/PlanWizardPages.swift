import CoreLocation
import SwiftUI

/// 計画を1ページずつ作る画面の、各ページの中身。
///
/// 流れ（どの順に進むか、いつ保存するか）は PlanWizardView に、
/// 見た目はこちらに分けています。1ファイルに収めると長くなりすぎて見通しが利かないためです。
extension PlanWizardView {
    func trailheadPage(_ plan: HikePlan) -> some View {
        PlanWizardStepPage(
            question: "どこに車を停めますか？",
            note: "山頂の近くの駐車場から選びます。登山口になる場所です。"
        ) {
            PlanWizardChoiceButton(
                title: plan.trailheadName == nil ? "駐車場を選ぶ" : "選び直す",
                systemImage: "parkingsign.circle.fill"
            ) { isPickingParking = true }

            if let name = plan.trailheadName {
                PlanWizardChosenRow(title: name, detail: plan.trailheadElevation.map { "標高 \(Int($0)) m" })
            }
            if isFetchingElevation {
                HStack { ProgressView(); Text("登山口の標高を調べています…") }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    func coursePage(_ plan: HikePlan) -> some View {
        PlanWizardStepPage(
            question: "どのコースで登りますか？",
            note: "調べてあるコースから選ぶと、コースタイムが正確になります。"
                + "選ばなければ、標高差から見積もります。"
        ) {
            PlanWizardChoiceButton(
                title: plan.routeName == nil ? "コースを選ぶ" : "選び直す",
                systemImage: "point.topleft.down.to.point.bottomright.curvepath"
            ) { isPickingRoute = true }

            if let route = plan.routeName {
                PlanWizardChosenRow(
                    title: route,
                    detail: "往復 \(TrackStatistics.hourMinuteText(plan.courseTimeSeconds))"
                )
            } else if plan.courseTimeSeconds > 0 {
                PlanWizardChosenRow(
                    title: "標高差からの見積もり",
                    detail: "往復 \(TrackStatistics.hourMinuteText(plan.courseTimeSeconds))"
                )
            }
        }
    }

    func originPage(_ plan: HikePlan) -> some View {
        PlanWizardStepPage(
            question: "どこから出発しますか？",
            note: "出発地が決まると、家を出る時刻まで逆算します。"
        ) {
            if let homeName = settings.homeName, let home = settings.homeCoordinate {
                PlanWizardChoiceButton(title: "自宅から（\(homeName)）", systemImage: "house.fill") {
                    setOrigin(homeName, home)
                }
            }
            PlanWizardChoiceButton(title: "現在地から", systemImage: "location.fill") {
                Task { await useCurrentLocation() }
            }
            PlanWizardChoiceButton(title: "住所・地名で探す", systemImage: "magnifyingglass") {
                isSearchingOrigin = true
            }

            if locationProvider.isLocating {
                HStack { ProgressView(); Text("現在地を調べています…") }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let message = locationProvider.errorMessage {
                Text(message).font(.caption).foregroundStyle(.red)
            }
            if let name = plan.originName {
                PlanWizardChosenRow(title: name, detail: nil)
            }
        }
    }

    func confirmPage(_ plan: HikePlan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.date.formatted(.dateTime.year().month().day().weekday()))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(plan.mountainName)
                        .font(.title.weight(.bold))
                }

                Group {
                    if let schedule = plan.schedule() {
                        PlanTimeline(plan: plan, schedule: schedule)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))

                if isCalculatingDrive {
                    HStack { ProgressView(); Text("車の時間を計算しています…") }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let driveError {
                    Text(driveError).font(.caption).foregroundStyle(.secondary)
                }

                Text("時刻は決めたあとでも「予定を調整する」から直せます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .task(id: "\(plan.originName ?? "")-\(plan.trailheadName ?? "")") {
            await calculateDrive(for: plan)
        }
    }
}

// MARK: - 日程のページ

/// 日付を選ぶページ。カレンダーを開いたまま見せ、選ぶだけで済むようにしています。
struct PlanWizardDatePage: View {
    @Bindable var plan: HikePlan

    var body: some View {
        PlanWizardStepPage(question: "いつ登りますか？", note: "日の出・日の入りから時間割を組みます。") {
            DatePicker(
                "登る日",
                selection: $plan.date,
                in: Calendar.current.startOfDay(for: Date())...,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .tint(Color.brandGreen)
            .padding(8)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

// MARK: - 部品

/// 1ページの骨組み。問いを1つ大きく出し、その下に選ぶものを並べます。
struct PlanWizardStepPage<Content: View>: View {
    let question: String
    let note: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(question)
                    .font(.title2.weight(.bold))
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                content
            }
            .padding(16)
        }
    }
}

struct PlanWizardChoiceButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(Color.brandGreen)
                    .frame(width: 28)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

/// いま選ばれているもの。
struct PlanWizardChosenRow: View {
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.brandGreen)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }
}
