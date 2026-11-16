import SwiftUI

/// 調査済みの登山ルートから選ぶ画面。
struct RoutePickerView: View {
    let routes: [CourseRoute]
    let onSelect: (CourseRoute) -> Void

    @Environment(\.dismiss) private var dismiss
    /// 車で来る前提だと、下山地点が違うルートは扱いにくい。既定では往復だけ見せます。
    @State private var onlyRoundTrip = true

    private var shown: [CourseRoute] {
        onlyRoundTrip ? routes.filter(\.isRoundTrip) : routes
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("往復できるルートだけ", isOn: $onlyRoundTrip)
                        .font(.subheadline)
                }

                Section {
                    ForEach(shown) { route in
                        Button {
                            onSelect(route)
                            dismiss()
                        } label: {
                            row(route)
                        }
                        .tint(.primary)
                    }
                } header: {
                    Text("\(shown.count) ルート")
                } footer: {
                    Text(
                        "出典: 十県一山域の日本百名山「登山ルートグレーディング」一覧表（各県公表）。\n"
                        + "体力度は 1〜10 で大きいほど体力を要し、難易度は A〜E で "
                        + "E ほど高度な登山技術を要します。"
                    )
                }
            }
            .navigationTitle("ルートを選ぶ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .overlay {
                if shown.isEmpty {
                    ContentUnavailableView(
                        "往復できるルートがありません",
                        systemImage: "arrow.triangle.swap",
                        description: Text("この山は縦走・周回のルートだけが登録されています。"
                                          + "上のスイッチを切ると表示できます。")
                    )
                }
            }
        }
    }

    private func row(_ route: CourseRoute) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(route.shortTitle)
                    .font(.body.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(TrackStatistics.hourMinuteText(route.courseTime))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.brandGreen)
            }

            Text("登山口: \(route.startName)（\(Int(route.startElevation))m）")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(route.gradeText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let warning = route.returnWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 3)
    }
}
