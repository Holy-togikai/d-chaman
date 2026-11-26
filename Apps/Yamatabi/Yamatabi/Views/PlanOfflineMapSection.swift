import SwiftData
import SwiftUI

/// 予定の画面に置く「オフライン地図をダウンロード」。
///
/// 範囲はアプリが山頂と登山口から自動で決めます（`OfflineAreaPlanner`）。
/// 利用者に範囲を選ばせると、広く表示したまま保存して膨大な通信が起きるためです。
struct PlanOfflineMapSection: View {
    let plan: HikePlan

    @Query private var areas: [OfflineArea]
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var downloader = OfflineMapDownloader.shared
    @State private var isConfirming = false

    private var planned: OfflineAreaPlanner.Plan? {
        OfflineAreaPlanner.plan(
            summit: plan.summitCoordinate,
            trailhead: plan.trailheadCoordinate,
            routeLengthKm: plan.routeLengthKm
        )
    }

    /// この予定の山頂と登山口をどちらも含む、保存済みの範囲。
    private var savedArea: OfflineArea? {
        areas.first { area in
            area.mountainID == plan.mountainID
                && area.box.contains(plan.summitCoordinate)
                && (plan.trailheadCoordinate.map(area.box.contains) ?? true)
        }
    }

    private var estimatedBytes: Int64 {
        Int64((planned?.tileCount ?? 0) * OfflineMapPolicy.estimatedBytesPerTile(.standard))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
            privateUseNotice
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .confirmationDialog(
            "オフライン地図を保存しますか？",
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button("保存する（約\(OfflineMapsView.format(estimatedBytes))）") { start() }
            Button("やめる", role: .cancel) {}
        } message: {
            Text("登山口と山頂のまわりの地図を、この端末に保存します。"
                 + "通信量が多いので、Wi-Fi につないでの保存をおすすめします。")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let savedArea, savedArea.id == downloader.currentAreaID {
            Label("オフライン地図を保存しています", systemImage: "arrow.down.circle")
                .font(.subheadline.weight(.medium))
            ProgressView(
                value: Double(downloader.finishedCount),
                total: Double(max(downloader.totalCount, 1))
            )
            Text("\(downloader.finishedCount) / \(downloader.totalCount) 枚")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        } else if let savedArea, savedArea.isComplete {
            Label("オフライン地図は保存済みです", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.brandGreen)
            Text("電波の無い場所でも、登山口と山頂のまわりの地図が見られます。"
                 + "（\(OfflineMapsView.format(savedArea.byteCount))）")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let planned {
            Button {
                isConfirming = true
            } label: {
                Label("オフライン地図をダウンロード", systemImage: "arrow.down.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.brandGreenDeep, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(downloader.isRunning)

            Text(caption(for: planned))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Label("この予定ではオフライン地図を保存できません", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
            Text("登山口が山頂から遠すぎて、保存できる量を超えます。登山口が正しいか確かめてください。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// 国土地理院から「アプリ上でもその旨記載いただけると幸いです」と依頼された注意書き（決定記録 0001）。
    /// 求められているのはこの旨の記載だけなので、リンクは付けず最小限の文にしている。消さないでください。
    private var privateUseNotice: some View {
        Text("保存した地図は私的利用の範囲でお使いください。範囲を超える場合は、国土地理院への申請が必要になることがあります。")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    private func caption(for planned: OfflineAreaPlanner.Plan) -> String {
        var text = "電波の無い山中に備えて、出発の前に保存してください。"
        if plan.trailheadCoordinate == nil {
            text += "登山口が決まっていないため、山頂のまわりを広めに保存します。"
        } else {
            text += "登山口から少し離れた駐車場まで含めて保存します。"
        }
        text += "約\(planned.tileCount.formatted())枚・約\(OfflineMapsView.format(estimatedBytes))。"
        if downloader.isRunning {
            text += "いまは別の地図を保存しています。終わってから押してください。"
        }
        return text
    }

    private func start() {
        guard let planned, !downloader.isRunning else { return }

        let area = OfflineArea(
            name: plan.mountainName,
            tile: .standard,
            box: planned.box,
            zooms: planned.zooms,
            mountainID: plan.mountainID
        )
        // 同じ山の古い範囲（登山口を変える前のものなど）は、新しい範囲に置き換える。
        // 一覧に同じ山が並ぶと、どれを消せばいいか分からなくなるため。
        let old = areas.filter { $0.mountainID == plan.mountainID }
        let kept = (areas.filter { $0.mountainID != plan.mountainID } + [area])
            .map { OfflineMapPolicy.KeptArea(tile: $0.tile, box: $0.box, zooms: $0.zooms) }
        for oldArea in old {
            for key in OfflineMapPolicy.removableKeys(of: oldArea.keys, keeping: kept) {
                OfflineTileStore.shared.remove(key)
            }
            modelContext.delete(oldArea)
        }

        modelContext.insert(area)
        try? modelContext.save()
        downloader.start(area)
    }
}
