import SwiftData
import SwiftUI

/// TOP画面。つぎの山行を、出発から帰りの寄り道まで1枚で見せます。
struct HomeView: View {
    @ObservedObject var tracker: LocationTracker
    /// 地図タブへ切り替える。記録中の帯や「記録を開始」から呼びます。
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

    private var plan: HikePlan? { HikePlan.next(from: plans, now: now) }

    var body: some View {
        NavigationStack {
            List {
                if let plan {
                    planSections(for: plan)
                } else {
                    emptySection
                }
                librarySection
            }
            .navigationTitle("山旅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("設定", systemImage: "gearshape")
                    }
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
    private func planSections(for plan: HikePlan) -> some View {
        let schedule = plan.schedule()
        let progress = HikeProgress.make(
            for: plan,
            schedule: schedule,
            isRecording: tracker.state != .idle,
            now: now
        )

        headerSection(for: plan, progress: progress)

        if tracker.state != .idle {
            Section {
                HomeRecordingBanner(
                    state: tracker.state,
                    statistics: tracker.statistics,
                    mountainName: tracker.mountainName,
                    remainingUntilDeadline: remainingUntilDescent(schedule),
                    onOpenMap: onOpenMap
                )
            }
        }

        Section {
            ForEach(HikeStage.allCases) { stage in
                HomeStageRow(
                    stage: stage,
                    state: progress.state(of: stage),
                    detail: detail(for: stage, plan: plan, schedule: schedule),
                    trailing: trailing(for: stage, plan: plan),
                    needsAttention: needsAttention(stage, plan: plan),
                    action: { open(stage, plan: plan) }
                )
            }
        } header: {
            Text("この山行の流れ")
        } footer: {
            Text("時刻は日の入りの1時間前までに下山できるよう逆算したものです。"
                 + "行をタップすると、その場面の画面を開きます。")
        }
    }

    /// 下山期限までの残り時間。
    ///
    /// 計画の日より前に試し録りしているときは出しません。何日も先の期限との差を
    /// 「下山まであと152時間」と出しても、画面が壊れて見えるだけだからです。
    private func remainingUntilDescent(_ schedule: HikeSchedule?) -> TimeInterval? {
        guard let schedule, now >= schedule.leaveHomeAt else { return nil }
        return schedule.descentDeadline.timeIntervalSince(now)
    }

    private func headerSection(for plan: HikePlan, progress: HikeProgress) -> some View {
        Section {
            Button {
                openedPlan = plan
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(headline(for: progress))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(plan.mountainName)
                        .font(.title3.weight(.semibold))
                    Text(subtitle(for: plan))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            .tint(.primary)

            if !plan.missingPieces.isEmpty {
                Label(
                    "\(plan.missingPieces.joined(separator: "・")) がまだ決まっていません",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
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

    // MARK: - 各段の中身

    private func detail(for stage: HikeStage, plan: HikePlan, schedule: HikeSchedule?) -> String? {
        switch stage {
        case .departure:
            return departureDetail(plan: plan, schedule: schedule)
        case .arrival:
            return arrivalDetail(plan: plan, schedule: schedule)
        case .hiking:
            guard let schedule else { return plan.routeName }
            let start = time(schedule.startHikingAt, on: plan)
            return "\(start) 歩き出す ・ \(TrackStatistics.hourMinuteText(schedule.courseTime))"
        case .meal:
            if plan.recipes.isEmpty { return "レシピを選ぶと買い出しリストを作ります" }
            let total = ShoppingListBuilder
                .build(from: plan.recipes, servings: plan.mealServings)
                .reduce(0) { $0 + $1.items.count }
            let done = plan.purchasedIngredientIDs.count
            return "\(plan.recipes.count)品 ・ 買い出し \(done)/\(total)"
        case .descent:
            guard let schedule else { return nil }
            let deadline = time(schedule.descentDeadline, on: plan)
            return "\(deadline)までに ・ 日の入り \(time(schedule.sunset, on: plan))"
        case .detour:
            // 寄り道は保存していないため、ここに出せるのは入口の案内だけです。
            return plan.trailheadCoordinate == nil
                ? "登山口を決めると探せます"
                : "温泉・食事処・道の駅を探す"
        }
    }

    private func departureDetail(plan: HikePlan, schedule: HikeSchedule?) -> String? {
        guard let schedule else { return "出発地と登山口を決めると時刻を出します" }
        var text = time(schedule.leaveHomeAt, on: plan)
        if let toll = plan.tollEstimate(for: UserSettings.shared.vehicleClass) {
            text += " ・ \(toll.amountText)"
        }
        return text
    }

    private func arrivalDetail(plan: HikePlan, schedule: HikeSchedule?) -> String? {
        guard let schedule else { return plan.trailheadName }
        let arrival = schedule.leaveHomeAt.addingTimeInterval(schedule.driveTime)
        var text = time(arrival, on: plan)
        if let trailhead = plan.trailheadName { text += " ・ \(trailhead)" }
        return text
    }

    private func trailing(for stage: HikeStage, plan: HikePlan) -> String? {
        guard stage == .departure, let drive = plan.driveTimeSeconds, drive > 0 else { return nil }
        return TrackStatistics.hourMinuteText(drive)
    }

    private func needsAttention(_ stage: HikeStage, plan: HikePlan) -> Bool {
        guard stage == .meal, !plan.recipes.isEmpty else { return false }
        let total = ShoppingListBuilder
            .build(from: plan.recipes, servings: plan.mealServings)
            .reduce(0) { $0 + $1.items.count }
        return plan.purchasedIngredientIDs.count < total
    }

    private func open(_ stage: HikeStage, plan: HikePlan) {
        switch stage {
        case .meal: mealPlan = plan
        case .detour: postHikePlan = plan
        // 時刻にまつわる段は、どれも計画画面で中身を直します。
        default: openedPlan = plan
        }
    }

    /// 「23:57」。登る日と違う日なら「前日 23:57」。
    private func time(_ date: Date, on plan: HikePlan) -> String {
        let text = date.formatted(date: .omitted, time: .shortened)
        guard !Calendar.current.isDate(date, inSameDayAs: plan.date) else { return text }
        return date < plan.date ? "前日 \(text)" : "翌日 \(text)"
    }

    // MARK: - 計画がないとき

    private var emptySection: some View {
        Section {
            Button {
                isChoosingMountain = true
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "mountain.2.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.brandGreen)
                    Text("つぎの山を決める")
                        .font(.subheadline.weight(.semibold))
                    Text("山を選ぶと、出発から帰りまでを組み立てます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }
            .tint(.primary)
        }
    }

    // MARK: - 下段

    private var librarySection: some View {
        Section {
            Button {
                isShowingPlans = true
            } label: {
                LabeledContent {
                    Text(plans.isEmpty ? "" : "\(plans.count) 件")
                } label: {
                    Label("すべての計画", systemImage: "calendar")
                }
            }
            Button {
                isShowingRecords = true
            } label: {
                Label("登山の記録", systemImage: "list.bullet.rectangle")
            }
        }
        .tint(.primary)
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
