import SwiftUI

/// 行動時間（ルート選択・標準コースタイム・ペース）のセクション。
struct PlanCourseTimeSection: View {
    @Bindable var plan: HikePlan

    @State private var isPickingRoute = false
    @State private var isEditingCourseTime = false

    /// この山について調査済みのルート。
    private var availableRoutes: [CourseRoute] {
        CourseRouteData.routes(for: plan.mountainID)
    }

    var body: some View {
        Section {
            if !availableRoutes.isEmpty {
                routeRows
            }

            Button {
                isEditingCourseTime = true
            } label: {
                LabeledContent(
                    "標準コースタイム（往復）",
                    value: plan.courseTimeSeconds > 0
                        ? TrackStatistics.hourMinuteText(plan.courseTimeSeconds)
                        : "未設定"
                )
            }
            .alert("標準コースタイム", isPresented: $isEditingCourseTime) {
                courseTimeInput
            } message: {
                Text("ガイドブックや登山地図に載っている往復の時間を、分単位で入力してください。")
            }

            Picker("ペース", selection: $plan.pace) {
                ForEach(HikePace.allCases) { pace in
                    Text("\(pace.label)（\(pace.detail)）").tag(pace)
                }
            }

            if plan.courseTimeSeconds > 0 {
                LabeledContent(
                    "あなたのペースでの行動時間",
                    value: TrackStatistics.hourMinuteText(plan.courseTimeSeconds * plan.pace.rawValue)
                )
                .fontWeight(.medium)
            }
        } header: {
            Text("行動時間")
        } footer: {
            Text(footerText)
        }
        .sheet(isPresented: $isPickingRoute) {
            RoutePickerView(routes: availableRoutes) { route in
                plan.apply(route: route)
            }
        }
    }

    @ViewBuilder
    private var routeRows: some View {
        Button {
            isPickingRoute = true
        } label: {
            LabeledContent(
                "登山ルート",
                value: plan.routeName ?? "選ぶ（\(availableRoutes.count)件）"
            )
        }
        if let startName = plan.routeStartName {
            LabeledContent("ルートの登山口", value: startName).font(.caption)
        }
        if let grade = plan.routeGradeText {
            LabeledContent("グレード", value: grade).font(.caption)
        }
        if plan.routeIsRoundTrip == false {
            Label(
                "往復ではないルートです。車の回収方法を確認してください。",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(.orange)
        }
    }

    private var footerText: String {
        guard plan.courseTimeSeconds > 0 else {
            return "登山口を選ぶと、標高差からおおよその時間を自動で入れます。"
        }
        if plan.courseTimeSource.needsCaution {
            return "⚠️ \(plan.courseTimeSource.label)です。標高差だけで計算しており水平距離を"
                + "考慮していないため、なだらかに長く歩く山では短く出ます。"
                + (availableRoutes.isEmpty
                   ? "ガイドブックの値が分かるなら上書きしてください。"
                   : "上の登山ルートから選ぶと、公表されている標準コースタイムを使えます。")
        }
        if plan.courseTimeSource == .researched {
            return "出典: 十県一山域の日本百名山「登山ルートグレーディング」一覧表（各県公表）。"
        }
        return plan.courseTimeSource.label + "を使っています。"
    }

    @ViewBuilder
    private var courseTimeInput: some View {
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
