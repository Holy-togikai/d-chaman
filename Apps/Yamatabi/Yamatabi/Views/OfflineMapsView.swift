import SwiftData
import SwiftUI

/// 電波の無い山中で地図を見るために、範囲を指定して地図を保存する画面。
///
/// 保存した地図を共有・書き出しする口は、意図して作っていません。
/// 国土地理院の回答（決定記録 0001）で申請不要とされたのは、利用者の私的利用に
/// 留まる場合だけだからです。
struct OfflineMapsView: View {
    /// 地図で今見えている範囲。これを保存します。
    let visibleBox: GeoBox?
    /// 地図で今表示しているタイルの種類。
    let tile: GSITile
    /// 保存名の初期値。地図で山を選んでいればその名前。
    let suggestedName: String?
    /// 保存した範囲を地図で見に行く。
    let onShow: (GeoBox) -> Void

    @Query(sort: \OfflineArea.createdAt, order: .reverse) private var areas: [OfflineArea]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var downloader = OfflineMapDownloader()

    @State private var name = ""
    @State private var storedBytes: Int64 = 0
    @State private var finishMessage: String?
    /// いま取っている最中の範囲。一覧で「途中で止めました」と取り違えないように見分ける。
    @State private var savingAreaID: UUID?

    var body: some View {
        NavigationStack {
            List {
                saveSection
                savedSection
                noticeSection
            }
            .navigationTitle("オフライン地図")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .disabled(downloader.isRunning)
                }
            }
            .alert(
                "保存しました",
                isPresented: .constant(finishMessage != nil),
                presenting: finishMessage
            ) { _ in
                Button("OK") { finishMessage = nil }
            } message: { message in
                Text(message)
            }
            .onAppear {
                if name.isEmpty { name = suggestedName ?? "保存した範囲" }
                refreshStoredBytes()
            }
            // 取っている途中で閉じると、取り終えた分だけが残って紛らわしいので、
            // 引き下げて閉じることも止める。
            .interactiveDismissDisabled(downloader.isRunning)
        }
    }

    // MARK: - 今見ている範囲を保存

    private var estimate: (count: Int, bytes: Int)? {
        guard let visibleBox else { return nil }
        let count = TileMath.count(of: visibleBox, zooms: OfflineMapPolicy.zooms)
        return (count, count * OfflineMapPolicy.estimatedBytesPerTile(tile))
    }

    private var isTooLarge: Bool {
        (estimate?.count ?? 0) > OfflineMapPolicy.maximumTilesPerArea
    }

    @ViewBuilder
    private var saveSection: some View {
        Section {
            if downloader.isRunning {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(
                        value: Double(downloader.finishedCount),
                        total: Double(max(downloader.totalCount, 1))
                    )
                    Text("\(downloader.finishedCount) / \(downloader.totalCount) 枚")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Button("やめる", role: .destructive) { downloader.cancel() }
            } else if let estimate {
                TextField("名前", text: $name)
                LabeledContent("地図の種類", value: tile.displayName)
                LabeledContent(
                    "量の見積もり",
                    value: "\(estimate.count.formatted())枚・約\(megabytes(Int64(estimate.bytes)))"
                )
                if isTooLarge {
                    Label(
                        "範囲が広すぎます。地図を拡大して、登る山の周りだけが映るようにしてください。",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(.orange)
                }
                Button {
                    save()
                } label: {
                    Label("今見ている範囲を保存", systemImage: "arrow.down.circle.fill")
                }
                .disabled(isTooLarge || name.trimmingCharacters(in: .whitespaces).isEmpty)
            } else {
                Text("地図を動かすと、見えている範囲を保存できます。")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("今見ている範囲を保存")
        } footer: {
            Text("電波の届く場所で、出発の前に保存してください。"
                 + "ズーム\(OfflineMapPolicy.zooms.lowerBound)〜\(OfflineMapPolicy.zooms.upperBound)を保存し、"
                 + "それより拡大したときは保存した地図を引き伸ばして表示します。"
                 + "1回に保存できるのは\(OfflineMapPolicy.maximumTilesPerArea.formatted())枚までです。")
        }
    }

    // MARK: - 保存した地図

    private var savedSection: some View {
        Section {
            if areas.isEmpty {
                Text("まだありません")
                    .foregroundStyle(.secondary)
            }
            ForEach(areas) { area in
                Button {
                    onShow(area.box)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(area.name).foregroundStyle(.primary)
                        Text(detail(for: area))
                            .font(.caption)
                            .foregroundStyle(
                                area.isComplete || area.id == savingAreaID ? Color.secondary : Color.orange
                            )
                    }
                }
                .disabled(downloader.isRunning)
            }
            .onDelete(perform: delete)
        } header: {
            Text("保存した地図")
        } footer: {
            if !areas.isEmpty {
                Text("合計 \(megabytes(storedBytes))。押すと、その範囲を地図で表示します。")
            }
        }
    }

    private func detail(for area: OfflineArea) -> String {
        if area.id == savingAreaID {
            return "\(area.tile.displayName) ・ 保存しています…"
        }
        var parts = [area.tile.displayName, "\(area.savedTileCount.formatted())枚"]
        if !area.isComplete { parts.append("途中で止めました") }
        return parts.joined(separator: " ・ ")
    }

    // MARK: - 注意書き

    /// 国土地理院から、アプリ上にも記載してほしいと依頼された内容です（決定記録 0001）。消さないでください。
    private var noticeSection: some View {
        Section {
            Text("保存した地図は、この端末の中で見るためだけのものです。"
                 + "保存した地図を公開・共有したり、それを使って別の地図や資料を作ったりする場合"
                 + "（私的利用の範囲を超える場合）は、国土地理院への申請が必要になることがあります。")
                .font(.footnote)
            if let url = URL(string: "https://www.gsi.go.jp/common/000223838.pdf#page=2") {
                Link("国土地理院の地図の利用手続", destination: url)
                    .font(.footnote)
            }
        } header: {
            Text("ご利用にあたって")
        }
    }

    // MARK: - 処理

    private func save() {
        guard let visibleBox else { return }
        let area = OfflineArea(
            name: name.trimmingCharacters(in: .whitespaces),
            tile: tile,
            box: visibleBox,
            zooms: OfflineMapPolicy.zooms
        )
        modelContext.insert(area)
        try? modelContext.save()

        savingAreaID = area.id
        downloader.start(area) { saved, completed in
            savingAreaID = nil
            area.savedTileCount = saved
            area.isComplete = completed
            try? modelContext.save()
            refreshStoredBytes()
            if completed {
                finishMessage = "「\(area.name)」を\(saved.formatted())枚保存しました。"
                    + "電波の無い場所でも、この範囲の地図が表示されます。"
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        let targets = offsets.map { areas[$0] }
        let others = areas
            .filter { area in !targets.contains { $0.id == area.id } }
            .map { OfflineMapPolicy.KeptArea(tile: $0.tile, box: $0.box, zooms: $0.zooms) }
        for area in targets {
            // 他の保存範囲と重なっているタイルは消さない。消すと、そちらが欠けるため。
            for key in OfflineMapPolicy.removableKeys(of: area.keys, keeping: others) {
                OfflineTileStore.shared.remove(key)
            }
            modelContext.delete(area)
        }
        try? modelContext.save()
        refreshStoredBytes()
    }

    private func refreshStoredBytes() {
        storedBytes = OfflineTileStore.shared.totalBytes()
    }

    private func megabytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
