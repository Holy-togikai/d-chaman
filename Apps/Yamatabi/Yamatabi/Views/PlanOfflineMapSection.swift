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
            Text("\(downloader.percent)%")
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
        } else if planned != nil {
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

            Text(caption)
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
    /// 申請に触れると登山アプリとして仰々しいため、人間の判断で一文に留めている。消さないでください。
    private var privateUseNotice: some View {
        Text("保存した地図は私的利用の範囲でお使いください。")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    /// ボタンの下に出す注記。利用者に要るのは通信量の目安だけなので、大きさだけを出す。
    /// 範囲の決め方（駐車場の余白など）の説明は、利用者には不要と判断した（人間の判断）。
    private var caption: String {
        var text = "約\(OfflineMapsView.format(estimatedBytes))"
        // 別の地図を保存している間はボタンが押せない。理由が分からないと困るので、そのときだけ添える。
        if downloader.isRunning {
            text += "（いまは別の地図を保存しています）"
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
