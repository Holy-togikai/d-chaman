import SwiftUI

/// 行動時間（ルート選択・標準コースタイム・ペース）のセクション。
struct PlanCourseTimeSection: View {
    @Bindable var plan: HikePlan
    /// この山について調査済みのルート。親から渡します。
    let availableRoutes: [CourseRoute]

    // シートやアラートの表示は親（PlanEditorView）に任せる。
    // Form の Section に付けた表示系の修飾子は各行に配られてしまい、
    // 同じフラグに束縛された画面が同時に複数立ち上がって navigation が壊れるため。
    let onPickRoute: () -> Void
    let onEditCourseTime: () -> Void

    var body: some View {
        Section {
            if !availableRoutes.isEmpty {
                routeRows
            }

            Button(action: onEditCourseTime) {
                LabeledContent(
                    "標準コースタイム（往復）",
                    value: plan.courseTimeSeconds > 0
                        ? TrackStatistics.hourMinuteText(plan.courseTimeSeconds)
                        : "未設定"
                )
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
    }

    @ViewBuilder
    private var routeRows: some View {
        Button(action: onPickRoute) {
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
}
