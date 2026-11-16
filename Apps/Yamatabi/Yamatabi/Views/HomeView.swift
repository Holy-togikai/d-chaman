import SwiftData
import SwiftUI

/// TOP画面。つぎの山行を、出発から帰りの寄り道まで1枚で見せます。
///
/// 標準のリストを使うと端末のテーマそのままの見た目になってしまうため、
/// アイコンの深緑を基調に組み立て直しています。
struct HomeView: View {
    @ObservedObject var tracker: LocationTracker
    /// 地図タブへ切り替える。記録中の帯や地図への導線から呼びます。
    let onOpenMap: () -> Void

    @Query(sort: \HikePlan.date, order: .forward) private var plans: [HikePlan]
    @Environment(\.modelContext) private var modelContext

    @State private var openedPlan: HikePlan?
    @State private var mealPlan: HikePlan?
    @State private var postHikePlan: HikePlan?
    @State private var isShowingPlans = false
    @State private var isShowingRecords = false
    @State private var isShowingSettings = false
    @State private var isChoosingMountain = false
    /// 1分ごとに進み具合を見直すための現在時刻。
    @State private var now = Date()

    private let mountains = MountainData.all
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var plan: HikePlan? { HikePlan.next(from: plans, now: now) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let plan {
                        planContent(for: plan)
                    } else {
                        emptyCard
                    }
                    libraryRow
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 64)
            }
            .background(Color.brandGreen.opacity(0.05).ignoresSafeArea())
            .navigationTitle("山旅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("設定", systemImage: "gearshape")
                    }
                    .tint(.brandGreen)
                }
            }
            .navigationDestination(item: $openedPlan) { plan in
                PlanEditorView(plan: plan)
            }
        }
        .onReceive(clock) { now = $0 }
        .sheet(item: $mealPlan) { MealPlanView(plan: $0) }
        .sheet(item: $postHikePlan) { PostHikeSpotsView(plan: $0) }
        .sheet(isPresented: $isShowingPlans) { PlanListView() }
        .sheet(isPresented: $isShowingRecords) { RecordListView() }
        .sheet(isPresented: $isShowingSettings) { SettingsView() }
        .sheet(isPresented: $isChoosingMountain) {
            MountainFinderView(mountains: mountains) { mountain in
                create(for: mountain)
            }
        }
    }

    // MARK: - 計画があるとき

    @ViewBuilder
    private func planContent(for plan: HikePlan) -> some View {
        let schedule = plan.schedule()
        let progress = HikeProgress.make(
            for: plan,
            schedule: schedule,
            isRecording: tracker.state != .idle,
            now: now
        )

        headerCard(for: plan, progress: progress)

        if tracker.state != .idle {
            HomeRecordingBanner(
                state: tracker.state,
                statistics: tracker.statistics,
                remainingUntilDeadline: remainingUntilDescent(schedule),
                onOpenMap: onOpenMap
            )
        }

        let content = HomeStageContent(plan: plan, schedule: schedule)
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(HikeStage.allCases) { stage in
                HomeStageTile(
                    stage: stage,
                    state: progress.state(of: stage),
                    value: content.value(for: stage),
                    caption: content.caption(for: stage),
                    needsAttention: content.needsAttention(stage),
                    action: { open(stage, plan: plan) }
                )
            }
        }
    }

    /// つぎの山行の見出し。アイコンと同じ深緑で塗り、山の稜線を敷いています。
    private func headerCard(for plan: HikePlan, progress: HikeProgress) -> some View {
        Button {
            openedPlan = plan
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(headline(for: progress))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
                Text(plan.mountainName)
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(subtitle(for: plan))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)

                if !plan.missingPieces.isEmpty {
                    Label(
                        plan.missingPieces.joined(separator: "・"),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.22), in: Capsule())
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(alignment: .bottomTrailing) {
                MountainSilhouette()
                    .fill(.white.opacity(0.12))
                    .frame(width: 150, height: 86)
                    .offset(x: 24, y: 18)
            }
            .background(Color.brandGreenDeep)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private func headline(for progress: HikeProgress) -> String {
        if let remaining = progress.timeUntilDeparture {
            let days = Int(remaining / (24 * 60 * 60))
            if days >= 1 { return "つぎの山行 ・ あと\(days)日" }
            return "つぎの山行 ・ あと\(TrackStatistics.hourMinuteText(remaining))"
        }
        if let current = progress.current { return "進行中 ・ \(current.title)" }
        return "つぎの山行"
    }

    private func subtitle(for plan: HikePlan) -> String {
        var parts = [plan.date.formatted(.dateTime.month().day().weekday())]
        if let trailhead = plan.trailheadName { parts.append(trailhead) }
        return parts.joined(separator: " ・ ")
    }

    /// 下山期限までの残り時間。
    ///
    /// 計画の日より前に試し録りしているときは出しません。何日も先の期限との差を
    /// 「下山まであと152時間」と出しても、画面が壊れて見えるだけだからです。
    private func remainingUntilDescent(_ schedule: HikeSchedule?) -> TimeInterval? {
        guard let schedule, now >= schedule.leaveHomeAt else { return nil }
        return schedule.descentDeadline.timeIntervalSince(now)
    }

    // MARK: - タイルの行き先

    private func open(_ stage: HikeStage, plan: HikePlan) {
        switch stage {
        case .meal: mealPlan = plan
        case .detour: postHikePlan = plan
        // 時刻にまつわる段は、どれも計画画面で中身を直します。
        default: openedPlan = plan
        }
    }

    // MARK: - 計画がないとき

    private var emptyCard: some View {
        Button {
            isChoosingMountain = true
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.white)
                Text("つぎの山を決める")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("山を選ぶと、出発から帰りまでを組み立てます。")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
            .padding(.horizontal, 18)
            .background(Color.brandGreenDeep)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 下段

    private var libraryRow: some View {
        HStack(spacing: 12) {
            shortcut("すべての計画", systemImage: "calendar", badge: plans.isEmpty ? nil : "\(plans.count)") {
                isShowingPlans = true
            }
            shortcut("登山の記録", systemImage: "figure.hiking", badge: nil) {
                isShowingRecords = true
            }
        }
    }

    private func shortcut(
        _ title: String,
        systemImage: String,
        badge: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 24))
                    .foregroundStyle(Color.brandGreen)
                Text(badge.map { "\(title) \($0)" } ?? title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.brandGreen.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func create(for mountain: Mountain) {
        // 既定は1週間後。天気予報が出ている範囲で、準備の時間も取れる距離感。
        let date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        let plan = HikePlan(mountain: mountain, date: date)
        modelContext.insert(plan)
        try? modelContext.save()
        openedPlan = plan
    }
}
