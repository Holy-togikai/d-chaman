import SwiftData
import SwiftUI

/// 登山計画の一覧。ここから新しい計画を作り、個々の計画を開きます。
struct PlanListView: View {
    @Query(sort: \HikePlan.date, order: .forward) private var plans: [HikePlan]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isChoosingMountain = false
    @State private var isShowingSettings = false
    @State private var newPlan: HikePlan?

    private let mountains = MountainData.all

    var body: some View {
        NavigationStack {
            List {
                ForEach(plans) { plan in
                    NavigationLink {
                        PlanEditorView(plan: plan)
                    } label: {
                        row(plan)
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("登山計画")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isChoosingMountain = true
                    } label: {
                        Label("計画を作る", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("設定", systemImage: "gearshape")
                    }
                }
            }
            .overlay {
                if plans.isEmpty {
                    ContentUnavailableView(
                        "計画がありません",
                        systemImage: "calendar",
                        description: Text("右上の＋から、登る山と日付を決めて計画を作れます。")
                    )
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $isChoosingMountain) {
                MountainListView(mountains: mountains) { mountain in
                    create(for: mountain)
                    isChoosingMountain = false
                }
            }
            .navigationDestination(item: $newPlan) { plan in
                PlanEditorView(plan: plan)
            }
        }
    }

    private func row(_ plan: HikePlan) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(plan.mountainName)
                    .font(.body.weight(.medium))
                if plan.missingPieces.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Text(plan.date.formatted(date: .long, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let schedule = plan.schedule(), plan.courseTimeSeconds > 0 {
                // 移動時間が分からないうちは出発時刻を出さない。
                // 間に合わない計画を信じてしまう危険があるため。
                if plan.driveTimeSeconds != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "car.fill")
                        Text("出発 " + schedule.leaveHomeAt.formatted(date: .omitted, time: .shortened))
                            .monospacedDigit()
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.blue)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "figure.hiking")
                        Text("歩き出す "
                             + schedule.startHikingAt.formatted(date: .omitted, time: .shortened))
                            .monospacedDigit()
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                }
            } else {
                Text("未入力: " + plan.missingPieces.joined(separator: "、"))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 3)
    }

    private func create(for mountain: Mountain) {
        // 既定は1週間後。天気予報が出ている範囲で、準備の時間も取れる距離感。
        let date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        let plan = HikePlan(mountain: mountain, date: date)
        modelContext.insert(plan)
        try? modelContext.save()
        newPlan = plan
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(plans[index])
        }
    }
}
