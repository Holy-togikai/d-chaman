import Foundation

/// TOP画面のタイルに出す文言を、計画から組み立てる係。
///
/// 絵記号が主役なので、文字はどれも短く切り詰めます。値はひと目で読める長さ、
/// 補足は読み飛ばしても困らないものだけ。
@MainActor
struct HomeStageContent {
    let plan: HikePlan
    let schedule: HikeSchedule?

    /// タイルの真ん中に大きく出す値。
    func value(for stage: HikeStage) -> String? {
        switch stage {
        case .departure:
            return schedule.map { time($0.leaveHomeAt) }
        case .arrival:
            return schedule.map { time($0.leaveHomeAt.addingTimeInterval($0.driveTime)) }
        case .hiking:
            return schedule.map { time($0.startHikingAt) }
        case .meal:
            return plan.recipes.isEmpty ? "選ぶ" : "\(plan.recipes.count) 品"
        case .descent:
            return schedule.map { time($0.descentDeadline) }
        case .detour:
            // 寄り道は何も保存していないので、ここは入口の案内だけです。
            return "探す"
        }
    }

    /// 値の下に小さく添える補足。
    func caption(for stage: HikeStage) -> String? {
        switch stage {
        case .departure:
            return driveCaption
        case .arrival:
            return plan.trailheadName
        case .hiking:
            return schedule.map { TrackStatistics.hourMinuteText($0.courseTime) }
        case .meal:
            guard !plan.recipes.isEmpty else { return nil }
            return "買い出し \(plan.purchasedIngredientIDs.count)/\(shoppingItemCount)"
        case .descent:
            return schedule.map { "日の入り \(time($0.sunset))" }
        case .detour:
            return plan.trailheadCoordinate == nil ? "登山口が必要" : "温泉・食事処"
        }
    }

    /// 注意を引きたいタイルか。いまのところ、買い出しが残っている山ごはんだけ。
    func needsAttention(_ stage: HikeStage) -> Bool {
        guard stage == .meal, !plan.recipes.isEmpty else { return false }
        return plan.purchasedIngredientIDs.count < shoppingItemCount
    }

    private var driveCaption: String? {
        guard let drive = plan.driveTimeSeconds, drive > 0 else { return nil }
        var text = TrackStatistics.hourMinuteText(drive)
        if let toll = plan.tollEstimate(for: UserSettings.shared.vehicleClass) {
            text += " ・ \(toll.amountText)"
        }
        return text
    }

    private var shoppingItemCount: Int {
        ShoppingListBuilder
            .build(from: plan.recipes, servings: plan.mealServings)
            .reduce(0) { $0 + $1.items.count }
    }

    /// 「23:57」。登る日と違う日なら「前日 23:57」。
    private func time(_ date: Date) -> String {
        let text = date.formatted(date: .omitted, time: .shortened)
        guard !Calendar.current.isDate(date, inSameDayAs: plan.date) else { return text }
        return date < plan.date ? "前日 \(text)" : "翌日 \(text)"
    }
}
