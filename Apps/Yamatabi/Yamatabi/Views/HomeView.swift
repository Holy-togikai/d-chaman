import SwiftData
import SwiftUI

/// TOP画面。予定している山の名前を並べ、新しい予定を立てる入口を一番上に置きます。
///
/// 以前は「つぎの山行」1件を6枚のタイルで見せていましたが、実機レビューで
/// 「絵が多くて分かりにくい」「別の山の計画を立てたいとき、どこへ行けばいいか分からない」
/// という指摘を受けました。このアプリの主役は「少ない入力で時間割ができること」なので、
/// ホームは予定の一覧と、予定を立てる入口に絞っています。
/// 時刻の流れは、予定を開いた先（PlanDetailView）で縦に並べて見せます。
struct HomeView: View {
    @ObservedObject var tracker: LocationTracker
    /// 地図タブへ切り替える。記録中の帯から呼びます。
    let onOpenMap: () -> Void

    @Query(sort: \HikePlan.date, order: .forward) private var plans: [HikePlan]

    @State private var openedPlan: HikePlan?
    @State private var mealPlan: HikePlan?
    @State private var isCreatingPlan = false
    @State private var isShowingPlans = false
    @State private var isShowingRecords = false
    @State private var isShowingSettings = false
    @State private var isExplainingMeal = false
    /// 1分ごとに「あと何日」と、終わった予定の入れ替えを見直すための現在時刻。
    @State private var now = Date()

    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    /// 終わっていない予定を、近い順に。件数で切らずにすべて並べます。
    ///
    /// 「ホームには予定している山がいつも見えていてほしい」という指摘のためです。
    /// 件数で切ると、立てたばかりの予定がホームに出ず、作れたのか分からなくなります。
    /// 終わった予定は「すべての計画を見る」から開けます。
    private var upcoming: [HikePlan] {
        plans
            .filter { now < $0.relevanceDeadline }
            .sorted { $0.departureReference < $1.departureReference }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if tracker.state != .idle {
                        HomeRecordingBanner(
                            state: tracker.state,
                            statistics: tracker.statistics,
                            remainingUntilDeadline: remainingUntilDescent,
                            onOpenMap: onOpenMap
                        )
                    }
                    createButton
                    upcomingSection
                    subTiles
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
                PlanDetailView(plan: plan)
            }
        }
        .onReceive(clock) { now = $0 }
        .fullScreenCover(isPresented: $isCreatingPlan) { PlanWizardView() }
        .sheet(item: $mealPlan) { MealPlanView(plan: $0) }
        .sheet(isPresented: $isShowingPlans) { PlanListView() }
        .sheet(isPresented: $isShowingRecords) { RecordListView() }
        .sheet(isPresented: $isShowingSettings) { SettingsView() }
        .alert("山ごはん", isPresented: $isExplainingMeal) {
            Button("山の予定を立てる") { isCreatingPlan = true }
            Button("閉じる", role: .cancel) {}
        } message: {
            Text("山ごはんは予定ごとに選びます。先に山の予定を立ててください。")
        }
    }

    // MARK: - 予定を立てる

    private var createButton: some View {
        Button {
            isCreatingPlan = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 34))
                VStack(alignment: .leading, spacing: 3) {
                    Text("山の予定を立てる")
                        .font(.title3.weight(.bold))
                    Text("山と日にちを選ぶだけで、時間割を組みます")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .bottomTrailing) {
                MountainSilhouette()
                    .fill(.white.opacity(0.12))
                    .frame(width: 150, height: 70)
                    .offset(x: 24, y: 14)
            }
            .background(Color.brandGreenDeep)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 直近の予定

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("直近の予定")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(upcoming) { plan in
                    Button {
                        openedPlan = plan
                    } label: {
                        planRow(plan)
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 16)
                }
                // まだ決まっていない枠。押せば次の予定を立て始められます。
                Button {
                    isCreatingPlan = true
                } label: {
                    placeholderRow
                }
                .buttonStyle(.plain)
            }
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))

            Button {
                isShowingPlans = true
            } label: {
                Text(plans.isEmpty ? "すべての計画を見る" : "すべての計画を見る（\(plans.count)件）")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .tint(.brandGreen)
        }
    }

    private func planRow(_ plan: HikePlan) -> some View {
        HStack(spacing: 14) {
            Text(plan.date.formatted(.dateTime.month(.defaultDigits).day()))
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(Color.brandGreen)
                .frame(width: 54, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.mountainName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(caption(for: plan))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private var placeholderRow: some View {
        HStack(spacing: 14) {
            Text("未定")
                .font(.headline)
                .frame(width: 54, alignment: .leading)
            Text(upcoming.isEmpty ? "まだ予定がありません" : "つぎの山を足す")
                .font(.body)
            Spacer(minLength: 0)
            Image(systemName: "plus.circle")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    /// 「あと3日 ・ 家を出る 4:30」。いちばん知りたい時刻を1つだけ添えます。
    private func caption(for plan: HikePlan) -> String {
        var parts: [String] = [plan.date.formatted(.dateTime.weekday())]
        if let days = daysUntil(plan) {
            parts.append(days == 0 ? "今日" : "あと\(days)日")
        }
        if let schedule = plan.schedule() {
            let headline = schedule.headline
            parts.append("\(headline.title) \(headline.date.formatted(date: .omitted, time: .shortened))")
        }
        return parts.joined(separator: " ・ ")
    }

    private func daysUntil(_ plan: HikePlan) -> Int? {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: plan.date)
        ).day
        return days.flatMap { $0 >= 0 ? $0 : nil }
    }

    // MARK: - サブ要素

    /// 過去の記録と山ごはん。あると楽しいが主役ではないので、下に小さく置く。
    private var subTiles: some View {
        HStack(spacing: 12) {
            subTile("過去の記録", systemImage: "figure.hiking") {
                isShowingRecords = true
            }
            subTile("山ごはん", systemImage: "fork.knife") {
                // 山ごはんは予定ごとに持つので、いちばん近い予定のものを開く。
                if let plan = upcoming.first {
                    mealPlan = plan
                } else {
                    isExplainingMeal = true
                }
            }
        }
    }

    private func subTile(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 24))
                    .foregroundStyle(Color.brandGreen)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.brandGreen.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 記録中

    /// 下山期限までの残り時間。記録中の帯に出します。
    ///
    /// 計画の日より前に試し録りしているときは出しません。何日も先の期限との差を
    /// 「下山まであと152時間」と出しても、画面が壊れて見えるだけだからです。
    private var remainingUntilDescent: TimeInterval? {
        guard let schedule = upcoming.first?.schedule() else { return nil }
        let start = schedule.leaveHomeAt ?? schedule.startHikingAt
        guard now >= start else { return nil }
        return schedule.descentAt.timeIntervalSince(now)
    }
}
