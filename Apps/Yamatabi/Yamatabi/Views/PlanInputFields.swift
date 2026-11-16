import SwiftUI

/// 標準コースタイムの手入力。アラートの中身として使います。
struct PlanCourseTimeInput: View {
    @Bindable var plan: HikePlan

    var body: some View {
        TextField(
            "分",
            value: Binding(
                get: { Int(plan.courseTimeSeconds / 60) },
                set: {
                    plan.courseTimeSeconds = TimeInterval($0 * 60)
                    plan.courseTimeSource = .manual
                }
            ),
            format: .number
        )
        .keyboardType(.numberPad)
        Button("OK") {}
        Button("キャンセル", role: .cancel) {}
    }
}

/// 高速料金の手入力。アラートの中身として使います。
struct PlanTollInput: View {
    @Bindable var plan: HikePlan
    let vehicle: VehicleClass

    var body: some View {
        TextField(
            "円",
            value: Binding(
                get: { plan.tollAmountOverride ?? plan.tollEstimate(for: vehicle)?.amount ?? 0 },
                set: { plan.tollAmountOverride = $0 }
            ),
            format: .number
        )
        .keyboardType(.numberPad)
        Button("OK") {}
        Button("概算に戻す", role: .destructive) { plan.tollAmountOverride = nil }
        Button("キャンセル", role: .cancel) {}
    }
}
