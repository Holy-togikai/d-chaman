import SwiftUI

/// 自家用車での移動を表示するセクション。
struct PlanDriveSection: View {
    @Bindable var plan: HikePlan
    let isCalculating: Bool
    let errorMessage: String?

    @State private var isEditingToll = false
    @ObservedObject private var settings = UserSettings.shared

    var body: some View {
        Section {
            if isCalculating {
                HStack {
                    ProgressView()
                    Text("経路を計算中…").foregroundStyle(.secondary)
                }
            } else if let seconds = plan.driveTimeSeconds {
                details(seconds: seconds)
            } else if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.secondary)
            } else {
                Text("出発地と登山口を設定すると計算します。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("移動（自家用車）")
        } footer: {
            if plan.tollEstimate(for: settings.vehicleClass)?.isManual == false {
                Text("高速料金は\(settings.vehicleClass.label)として、"
                     + "対距離料金（普通車 24.6円/km＋150円）から概算したものです。"
                     + "NEXCO は料金を取得できる公開APIを提供していないため、"
                     + "深夜割引・休日割引・大都市近郊区間の割増は反映されません。")
            }
        }
    }

    @ViewBuilder
    private func details(seconds: TimeInterval) -> some View {
        LabeledContent("移動時間", value: TrackStatistics.hourMinuteText(seconds))

        if let distance = plan.driveDistance {
            LabeledContent("距離", value: String(format: "%.1f km", distance / 1000))
        }
        if let names = plan.highwayNamesText, !names.isEmpty {
            LabeledContent("通る高速道路", value: names)
        }
        if let toll = plan.tollEstimate(for: settings.vehicleClass) {
            Button {
                isEditingToll = true
            } label: {
                LabeledContent(
                    toll.isManual ? "高速料金" : "高速料金（概算）",
                    value: toll.amountText
                )
            }
            .alert("高速料金", isPresented: $isEditingToll) {
                tollInput
            } message: {
                Text("ドラぷら等で調べた金額を円単位で入力すると、概算を上書きできます。")
            }
        }
        Link(destination: TollEstimate.driveplazaURL) {
            Label("ドラぷらで正確な料金を調べる", systemImage: "arrow.up.right.square")
        }
    }

    @ViewBuilder
    private var tollInput: some View {
        TextField(
            "円",
            value: Binding(
                get: { plan.tollAmountOverride
                    ?? plan.tollEstimate(for: settings.vehicleClass)?.amount ?? 0 },
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
