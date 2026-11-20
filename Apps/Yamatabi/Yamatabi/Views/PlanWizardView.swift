import CoreLocation
import SwiftData
import SwiftUI

/// 新しい予定を1項目1ページで作る画面。
///
/// 山を選んだ直後に入力欄の並んだ画面を出していたところ、「文字の壁で、慣れる前に
/// やめてしまいそう」という指摘を受けました。1ページで決めることを1つに絞り、
/// 「戻る」「次へ」で進めるようにしています。登山口と出発地は後回しにもできます。
///
/// 計画は最後の「この予定で決める」まで保存しません。途中でやめたときに、
/// 作りかけの予定がホームに残らないようにするためです。
struct PlanWizardView: View {
    /// 地図で山を選んでから始めたときは、山を選ぶページを飛ばす。
    var initialMountain: Mountain?
    /// 予定を決めたあとに呼ぶ。地図から始めたときにホームへ戻すのに使います。
    var onFinish: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject var locationProvider = CurrentLocationProvider()
    @ObservedObject var settings = UserSettings.shared

    @State private var draft: HikePlan?
    @State private var step: Step = .mountain

    @State var isPickingParking = false
    @State var isPickingRoute = false
    @State var isSearchingOrigin = false
    @State var isFetchingElevation = false
    @State var isCalculatingDrive = false
    @State var driveError: String?

    private let mountains = MountainData.all

    enum Step: Int, CaseIterable {
        case mountain, date, trailhead, course, origin, confirm

        var title: String {
            switch self {
            case .mountain: "山を選ぶ"
            case .date: "日程を決める"
            case .trailhead: "駐車場を決める"
            case .course: "コースを決める"
            case .origin: "出発地を決める"
            case .confirm: "予定を確かめる"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressBar
                page
                    .frame(maxHeight: .infinity, alignment: .top)
                if step != .mountain || draft != nil {
                    bottomBar
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if step == firstStep {
                        Button("やめる") { dismiss() }
                    } else {
                        Button {
                            goBack()
                        } label: {
                            Label("戻る", systemImage: "chevron.left")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                }
            }
        }
        .tint(.brandGreen)
        .sheet(isPresented: $isPickingParking) {
            if let draft {
                ParkingPickerView(summit: draft.summitCoordinate) { spot in
                    applyTrailhead(spot.name, spot.coordinate)
                }
            }
        }
        .sheet(isPresented: $isPickingRoute) {
            if let draft {
                RoutePickerView(routes: routes(for: draft)) { route in
                    draft.apply(route: route)
                }
            }
        }
        .sheet(isPresented: $isSearchingOrigin) {
            if let draft {
                PlaceSearchView(
                    center: draft.summitCoordinate,
                    initialQuery: settings.homeName ?? ""
                ) { name, coordinate in
                    setOrigin(name, coordinate)
                }
            }
        }
        .onAppear(perform: startFromInitialMountain)
    }

    // MARK: - 進み具合

    /// 実際に通るページ。調査済みのルートが無い山では、コースのページを飛ばします。
    private var steps: [Step] {
        Step.allCases.filter { $0 != .course || hasRoutes }
    }

    private var firstStep: Step { initialMountain == nil ? .mountain : .date }

    private var hasRoutes: Bool {
        guard let draft else { return false }
        return !routes(for: draft).isEmpty
    }

    private var progressBar: some View {
        let shown = steps.filter { $0.rawValue >= firstStep.rawValue }
        let index = (shown.firstIndex(of: step) ?? 0) + 1
        return VStack(spacing: 6) {
            ProgressView(value: Double(index), total: Double(shown.count))
            Text("\(index) / \(shown.count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func goNext() {
        guard let index = steps.firstIndex(of: step), index + 1 < steps.count else { return }
        step = steps[index + 1]
    }

    private func goBack() {
        guard let index = steps.firstIndex(of: step), index > 0 else { return }
        step = steps[index - 1]
    }

    // MARK: - 各ページ
    // 山を選ぶ以外のページの中身は PlanWizardPages.swift にあります。

    @ViewBuilder
    private var page: some View {
        switch step {
        case .mountain:
            MountainFinderContent(mountains: mountains, onSelect: select)
        case .date:
            if let draft { PlanWizardDatePage(plan: draft) }
        case .trailhead:
            if let draft { trailheadPage(draft) }
        case .course:
            if let draft { coursePage(draft) }
        case .origin:
            if let draft { originPage(draft) }
        case .confirm:
            if let draft { confirmPage(draft) }
        }
    }

    // MARK: - 下の帯

    private var bottomBar: some View {
        Button {
            if step == .confirm {
                finish()
            } else {
                goNext()
            }
        } label: {
            Text(nextTitle)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.brandGreenDeep, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    /// まだ決めていない項目では「あとで決める」と出す。
    /// 「次へ」のままだと、決めずに進んでよいのかが分からないためです。
    private var nextTitle: String {
        switch step {
        case .confirm: return "この予定で決める"
        case .trailhead where draft?.trailheadName == nil: return "あとで決める"
        case .course where draft?.routeName == nil: return "見積もりで進む"
        case .origin where draft?.originName == nil: return "あとで決める"
        default: return "次へ"
        }
    }

    // MARK: - 処理

    private func startFromInitialMountain() {
        guard draft == nil, let initialMountain else { return }
        draft = HikePlan(mountain: initialMountain, date: Self.defaultDate)
        step = .date
    }

    /// 既定は1週間後。天気予報が出ている範囲で、準備の時間も取れる距離感。
    private static var defaultDate: Date {
        Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    }

    private func select(_ mountain: Mountain) {
        if let draft {
            draft.change(to: mountain)
        } else {
            draft = HikePlan(mountain: mountain, date: Self.defaultDate)
        }
        goNext()
    }

    private func routes(for plan: HikePlan) -> [CourseRoute] {
        CourseRouteData.routes(for: plan.mountainID)
    }

    private func applyTrailhead(_ name: String, _ coordinate: CLLocationCoordinate2D) {
        guard let draft else { return }
        // 登山口が変われば車の時間も変わる。古い値で時刻を出さないよう消しておく。
        draft.driveTimeSeconds = nil
        isFetchingElevation = true
        Task {
            await draft.applyTrailhead(name: name, coordinate: coordinate)
            isFetchingElevation = false
        }
    }

    func setOrigin(_ name: String, _ coordinate: CLLocationCoordinate2D) {
        draft?.setOrigin(name: name, coordinate: coordinate)
        draft?.driveTimeSeconds = nil
    }

    func useCurrentLocation() async {
        // 失敗の理由は locationProvider.errorMessage に入り、画面に出る。
        guard let location = try? await locationProvider.current() else { return }
        setOrigin("現在地", location.coordinate)
    }

    func calculateDrive(for plan: HikePlan) async {
        guard plan.driveTimeSeconds == nil,
              plan.originCoordinate != nil,
              plan.trailheadCoordinate != nil else { return }
        isCalculatingDrive = true
        driveError = nil
        defer { isCalculatingDrive = false }
        do {
            try await plan.refreshDrive()
        } catch {
            driveError = "車の時間を計算できませんでした。決めたあとで計算し直せます。"
        }
    }

    private func finish() {
        guard let draft else { return }
        modelContext.insert(draft)
        try? modelContext.save()
        onFinish()
        dismiss()
    }
}
