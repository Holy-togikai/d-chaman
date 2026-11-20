import SwiftData
import SwiftUI

/// 地図タブ。山を探し、軌跡を見ながら記録を取ります。
///
/// `LocationTracker` は `RootView` が持っているものを受け取ります。ここで `@StateObject`
/// として持つと、タブを移った拍子に記録が止まってしまいます。
struct MapTabView: View {
    @ObservedObject var tracker: LocationTracker
    /// 地図から予定を決めたあとに呼ぶ。ホームへ戻して、並んだ予定を見せるのに使います。
    var onPlanCreated: () -> Void = {}

    /// 表示中のタイル種別。
    @State private var tile: GSITile = .standard
    /// 選択中の山。
    @State private var selected: Mountain?
    /// 山を探すシートを出しているか。
    @State private var isSearching = false
    /// 登山記録の一覧を出しているか。
    @State private var isShowingRecords = false
    /// 「終了」を押したあとの確認。
    @State private var isConfirmingFinish = false
    /// 保存できなかったときの通知。
    @State private var saveFailureMessage: String?
    /// 地図で選んだ山。予定を立て始めると、1ページずつの作成画面を出します。
    @State private var planningMountain: Mountain?

    /// 下部のパネルとタブバーが地図に重なる高さ。出典表示を隠さないために測っています。
    @State private var bottomOverlayHeight: CGFloat = 0

    @Environment(\.modelContext) private var modelContext

    private let mountains = MountainData.all

    var body: some View {
        GSIMapView(
            tile: tile,
            annotations: mountains.map(MountainAnnotation.init),
            focused: selected,
            track: tracker.points,
            showsUserLocation: tracker.state != .idle,
            followsTrack: tracker.state == .recording,
            onSelect: { selected = $0.mountain },
            attributionBottomInset: bottomOverlayHeight
        )
        .ignoresSafeArea()
        .overlay(alignment: .top) { topBar }
        // 下部の帯は safeAreaInset で差し込む。
        // ZStack の子として重ねると、地図側のビューと重なってタップが届かなくなるため。
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 6) {
                RecordingPanel(
                    state: tracker.state,
                    statistics: tracker.statistics,
                    mountainName: tracker.state == .idle ? selected?.name : tracker.mountainName,
                    onStart: { tracker.start(mountainName: selected?.displayName, mountainID: selected?.id) },
                    onPlan: selected.map { mountain in { planningMountain = mountain } },
                    onPause: tracker.pause,
                    onResume: tracker.resume,
                    onFinish: { isConfirmingFinish = true }
                )
                .background {
                    GeometryReader { proxy in
                        Color.clear.onChange(
                            of: proxy.size.height + proxy.safeAreaInsets.bottom,
                            initial: true
                        ) { _, height in
                            bottomOverlayHeight = height
                        }
                    }
                }
            }
        }
        .fullScreenCover(item: $planningMountain) { mountain in
            // 山は地図で選び終えているので、日程のページから始める。
            PlanWizardView(initialMountain: mountain, onFinish: onPlanCreated)
        }
        .sheet(isPresented: $isSearching) {
            MountainFinderView(mountains: mountains) { mountain in
                selected = mountain
            }
        }
        .sheet(isPresented: $isShowingRecords) {
            RecordListView()
        }
        // confirmationDialog ではキャンセルボタンが表示されない場合があり、
        // 記録を止めるという取り返しのつかない操作で逃げ道が見えないのは危ないため、
        // 2つのボタンが必ず並ぶ alert を使う。
        .alert("記録を終了しますか？", isPresented: $isConfirmingFinish) {
            Button("続ける", role: .cancel) {}
            Button("終了して保存", role: .destructive) { finishAndSave() }
        } message: {
            Text("ここまでの軌跡を登山記録として保存します。")
        }
        .alert(
            "記録を保存できませんでした",
            isPresented: .constant(saveFailureMessage != nil),
            presenting: saveFailureMessage
        ) { _ in
            Button("OK") { saveFailureMessage = nil }
        } message: { message in
            Text(message)
        }
        .alert(
            "位置情報が使えません",
            isPresented: .constant(tracker.problem == .permissionDenied)
        ) {
            Button("設定を開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("閉じる", role: .cancel) {}
        } message: {
            Text("登山の軌跡を記録するには、位置情報の利用を許可してください。")
        }
    }

    // MARK: - 操作バー

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                isSearching = true
            } label: {
                Label(selected?.displayName ?? "山を探す", systemImage: "magnifyingglass")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
            }

            Spacer()

            Button {
                isShowingRecords = true
            } label: {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 40, height: 40)
                    .background(.regularMaterial, in: Circle())
            }

            Menu {
                Picker("地図の種類", selection: $tile) {
                    ForEach(GSITile.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
            } label: {
                Image(systemName: "square.3.layers.3d")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 40, height: 40)
                    .background(.regularMaterial, in: Circle())
            }
        }
        .tint(.primary)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - 保存

    private func finishAndSave() {
        guard let result = tracker.finish() else {
            saveFailureMessage = "軌跡がほとんど記録されていませんでした。屋外で電波と空の見える場所をお試しください。"
            return
        }

        let record = HikeRecord(
            mountainName: result.mountainName,
            mountainID: result.mountainID,
            startedAt: result.startedAt,
            endedAt: Date(),
            points: result.points,
            statistics: result.statistics
        )
        modelContext.insert(record)

        do {
            try modelContext.save()
            isShowingRecords = true
        } catch {
            saveFailureMessage = "保存時にエラーが発生しました（\(error.localizedDescription)）"
        }
    }
}

#Preview {
    MapTabView(tracker: LocationTracker())
        .modelContainer(for: [HikeRecord.self, HikePlan.self], inMemory: true)
}
