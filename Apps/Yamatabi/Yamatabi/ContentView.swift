import SwiftData
import SwiftUI

struct ContentView: View {
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

    @StateObject private var tracker = LocationTracker()
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
            onSelect: { selected = $0.mountain }
        )
        .ignoresSafeArea()
        .overlay(alignment: .top) { topBar }
        // 下部の帯は safeAreaInset で差し込む。
        // ZStack の子として重ねると、地図側のビューと重なってタップが届かなくなるため。
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 6) {
                HStack {
                    attribution
                    Spacer()
                }
                .padding(.horizontal, 12)

                RecordingPanel(
                    state: tracker.state,
                    statistics: tracker.statistics,
                    mountainName: tracker.state == .idle ? selected?.name : tracker.mountainName,
                    onStart: { tracker.start(mountainName: selected?.name) },
                    onPause: tracker.pause,
                    onResume: tracker.resume,
                    onFinish: { isConfirmingFinish = true }
                )
            }
        }
        .sheet(isPresented: $isSearching) {
            MountainListView(mountains: mountains) { mountain in
                selected = mountain
                isSearching = false
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
                Label(selected?.name ?? "山を探す", systemImage: "magnifyingglass")
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

    /// 出典表示。地理院タイルの利用条件として明示が必要です。消さないでください。
    private var attribution: some View {
        Link(destination: URL(string: "https://maps.gsi.go.jp/development/ichiran.html")!) {
            Text("地理院タイル")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
        }
        .tint(.secondary)
    }

    // MARK: - 保存

    private func finishAndSave() {
        guard let result = tracker.finish() else {
            saveFailureMessage = "軌跡がほとんど記録されていませんでした。屋外で電波と空の見える場所をお試しください。"
            return
        }

        let record = HikeRecord(
            mountainName: result.mountainName,
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

/// 山を名前・かな・都道府県で絞り込んで選ぶ画面。
struct MountainListView: View {
    let mountains: [Mountain]
    let onSelect: (Mountain) -> Void

    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var results: [Mountain] {
        mountains
            .filter { $0.matches(query) }
            .sorted { $0.elevation > $1.elevation }
    }

    var body: some View {
        NavigationStack {
            List(results) { mountain in
                Button {
                    onSelect(mountain)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(mountain.name)
                                    .font(.body.weight(.medium))
                                if mountain.isHyakumeizan {
                                    Text("百名山")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.18), in: Capsule())
                                        .foregroundStyle(.green)
                                }
                            }
                            Text(mountain.prefectureText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(mountain.elevation)m")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.primary)
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "山名・ふりがな・都道府県")
            .navigationTitle("山を探す")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: HikeRecord.self, inMemory: true)
}
