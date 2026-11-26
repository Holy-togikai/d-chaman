import SwiftUI

/// 山ごはんと下山後の寄り道への入口。
struct PlanExtrasSection: View {
    let plan: HikePlan
    let onOpenMeals: () -> Void
    let onOpenPostHike: () -> Void

    var body: some View {
        Section {
            Button(action: onOpenMeals) {
                LabeledContent {
                    Text(plan.recipes.isEmpty ? "" : "\(plan.recipes.count) 品")
                } label: {
                    Label("山ごはんを決める", systemImage: "fork.knife")
                }
            }

            Button(action: onOpenPostHike) {
                Label("下山後に寄る場所を探す", systemImage: "mappin.and.ellipse")
            }
        } footer: {
            Text("レシピを選ぶと買い出しリストを作ります。"
                 + "下山後は、登山口の周りから温泉・食事処・道の駅を探します。")
        }
    }
}
