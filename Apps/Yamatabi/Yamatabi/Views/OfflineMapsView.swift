import SwiftData
import SwiftUI

/// 「オフライン地図」タブ。端末に保存した地図の一覧と、容量の管理をする画面です。
///
/// 地図を保存するのは予定の画面から（範囲はアプリが自動で決めます）。ここでは
/// 何がどれだけ入っているかを見て、要らないものを消すことに絞っています。
///
/// 保存した地図を共有・書き出しする口は、意図して作っていません。
/// 国土地理院の回答（決定記録 0001）で申請不要とされたのは、利用者の私的利用に
/// 留まる場合だけだからです。
struct OfflineMapsView: View {
    /// 保存した範囲を地図タブで見せる。
    let onShow: (GeoBox) -> Void

    @Query(sort: \OfflineArea.createdAt, order: .reverse) private var areas: [OfflineArea]
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var downloader = OfflineMapDownloader.shared

    @State private var storedBytes: Int64 = 0
    @State private var freeBytes: Int64?

    var body: some View {
        NavigationStack {
            List {
                if downloader.isRunning {
                    progressSection
                }
                capacitySection
                areasSection
            }
            .navigationTitle("オフライン地図")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !areas.isEmpty {
                    EditButton().disabled(downloader.isRunning)
                }
            }
            .overlay {
                if areas.isEmpty && !downloader.isRunning {
                    EmptyStateView(
                        title: "保存した地図はありません",
                        message: "予定の画面の「オフライン地図をダウンロード」から、"
                            + "登山口と山頂のまわりの地図を保存できます。電波の無い山中でも地図が見られます。",
                        systemImage: "arrow.down.circle"
                    )
                }
            }
            .onAppear(perform: refreshCapacity)
            // 取り終えたら、使用量を見直す。
            .onChange(of: downloader.isRunning) { _, _ in refreshCapacity() }
        }
    }

    // MARK: - 取得中

    private var progressSection: some View {
        Section("保存しています") {
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
        }
    }

    // MARK: - 容量

    private var capacitySection: some View {
        Section {
            LabeledContent("保存した地図", value: Self.format(storedBytes))
            if let freeBytes {
                LabeledContent("端末の空き", value: Self.format(freeBytes))
            }
        } header: {
            Text("容量")
        }
    }

    // MARK: - 一覧

    private var areasSection: some View {
        Section {
            ForEach(areas) { area in
                Button {
                    onShow(area.box)
                } label: {
                    row(area)
                }
                .disabled(area.id == downloader.currentAreaID)
            }
            .onDelete(perform: delete)
        } header: {
            if !areas.isEmpty { Text("保存した地図") }
        } footer: {
            if !areas.isEmpty {
                Text("押すと、その範囲を地図で表示します。左にずらすと消せます。")
            }
        }
    }

    private func row(_ area: OfflineArea) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(area.name).foregroundStyle(.primary)
                Text(detail(for: area))
                    .font(.caption)
                    .foregroundStyle(isUnfinished(area) ? Color.orange : Color.secondary)
            }
            Spacer()
            if area.id != downloader.currentAreaID {
                Text(Self.format(area.byteCount))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func isUnfinished(_ area: OfflineArea) -> Bool {
        !area.isComplete && area.id != downloader.currentAreaID
    }

    private func detail(for area: OfflineArea) -> String {
        if area.id == downloader.currentAreaID {
            return "保存しています…"
        }
        var parts = [
            area.createdAt.formatted(.dateTime.month().day()),
            "\(area.savedTileCount.formatted())枚"
        ]
        if !area.isComplete { parts.append("途中で止めました") }
        return parts.joined(separator: " ・ ")
    }

    // MARK: - 処理

    private func delete(at offsets: IndexSet) {
        let targets = offsets.map { areas[$0] }.filter { $0.id != downloader.currentAreaID }
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
        refreshCapacity()
    }

    private func refreshCapacity() {
        storedBytes = OfflineTileStore.shared.totalBytes()
        let home = URL(fileURLWithPath: NSHomeDirectory())
        freeBytes = (try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
