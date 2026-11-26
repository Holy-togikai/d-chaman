import SwiftData
import SwiftUI

/// 1つの予定を開いたときの画面。時刻の縦並びを主役にしています。
///
/// 細かい入力欄は「予定を調整する」の先（PlanEditorView）に退けました。
/// 開いてすぐ入力欄の壁が見えると、何が決まっていて何が足りないのかが読み取れないためです。
struct PlanDetailView: View {
    let plan: HikePlan

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingMeals = false
    @State private var isShowingPostHike = false
    @State private var isConfirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                Group {
                    if let schedule = plan.schedule() {
                        PlanTimeline(plan: plan, schedule: schedule)
                    } else {
                        // 極地のように日の出日の入りが無い日だけ起きる。日本の山ではまず出ない。
                        Text("この日は日の出・日の入りを計算できないため、時間割を組めません。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))

                NavigationLink {
                    PlanEditorView(plan: plan)
                } label: {
                    Text("予定を調整する")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.brandGreenDeep, in: RoundedRectangle(cornerRadius: 14))
                }

                // 山に入る前に済ませておくこと。時間割のすぐ下に置き、見落とされないようにする。
                PlanOfflineMapSection(plan: plan)

                extras
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color.brandGreen.opacity(0.05).ignoresSafeArea())
        .navigationTitle(plan.mountainName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("この予定を削除", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                } label: {
                    Label("その他", systemImage: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "\(plan.mountainName)の予定を削除しますか？",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("削除する", role: .destructive) {
                // 先に画面を閉じてから消す。表示中に消すと、消えた計画を描こうとして落ちるため。
                dismiss()
                let context = modelContext
                let target = plan
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    context.delete(target)
                    try? context.save()
                }
            }
        } message: {
            Text("削除すると元に戻せません。")
        }
        .sheet(isPresented: $isShowingMeals) { MealPlanView(plan: plan) }
        .sheet(isPresented: $isShowingPostHike) { PostHikeSpotsView(plan: plan) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(plan.date.formatted(.dateTime.year().month().day().weekday()))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(plan.mountainName)
                .font(.largeTitle.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let route = plan.routeName {
                Text(route)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 山ごはんと帰りの寄り道。あると楽しいが、時間割の外にあるものなので控えめに置く。
    private var extras: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("あわせて決める")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                extraButton("山ごはん", systemImage: "fork.knife", detail: mealDetail) {
                    isShowingMeals = true
                }
                extraButton("帰りの寄り道", systemImage: "mappin.and.ellipse", detail: nil) {
                    isShowingPostHike = true
                }
            }
        }
    }

    private var mealDetail: String? {
        let count = plan.recipes.count
        return count == 0 ? nil : "\(count)品"
    }

    private func extraButton(
        _ title: String,
        systemImage: String,
        detail: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.brandGreen)
                Text(title)
                    .foregroundStyle(.primary)
                if let detail {
                    Text(detail).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color.brandGreen.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
