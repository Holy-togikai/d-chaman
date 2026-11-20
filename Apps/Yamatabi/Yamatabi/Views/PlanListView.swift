import SwiftData
import SwiftUI

/// 登山計画の一覧。ここから新しい計画を作り、個々の計画を開きます。
struct PlanListView: View {
    @Query(sort: \HikePlan.date, order: .forward) private var plans: [HikePlan]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isChoosingMountain = false
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(plans) { plan in
                    NavigationLink {
                        PlanDetailView(plan: plan)
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
                    EmptyStateView(
                        title: "計画がありません",
                        message: "右上の＋から、登る山と日付を決めて計画を作れます。",
                        systemImage: "calendar"
                    )
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            // 作り方はホームと同じ1ページずつの流れにそろえる。入口によって
            // 作り方が違うと、どちらかに慣れた人が戸惑うためです。
            .fullScreenCover(isPresented: $isChoosingMountain) {
                PlanWizardView()
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
                        .foregroundStyle(Color.brandGreen)
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
                        Text("出発 " + (schedule.leaveHomeAt ?? schedule.startHikingAt)
                            .formatted(date: .omitted, time: .shortened))
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
                    .foregroundStyle(Color.brandGreen)
                }
            } else {
                Text("未入力: " + plan.missingPieces.joined(separator: "、"))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 3)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(plans[index])
        }
    }
}
