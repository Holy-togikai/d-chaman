import SwiftData
import SwiftUI

/// 保存済みの登山記録の一覧。
struct RecordListView: View {
    @Query(sort: \HikeRecord.startedAt, order: .reverse) private var records: [HikeRecord]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(records) { record in
                    NavigationLink {
                        RecordDetailView(record: record)
                    } label: {
                        row(record)
                    }
                }
                .onDelete(perform: delete)
            }
            .listStyle(.plain)
            .navigationTitle("登山記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .overlay {
                if records.isEmpty {
                    EmptyStateView(
                        title: "記録がありません",
                        message: "山を選んで「記録を開始」すると、ここに残ります。",
                        systemImage: "figure.hiking"
                    )
                }
            }
        }
    }

    private func row(_ record: HikeRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(record.title)
                .font(.body.weight(.medium))

            Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                summary("figure.walk", record.statistics.distanceText)
                summary("arrow.up.right", record.statistics.elevationGainText)
                summary("clock", record.statistics.elapsedText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func summary(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(text).monospacedDigit()
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(records[index])
        }
    }
}

/// 1件の記録の詳細。軌跡を地図に重ねて表示します。
struct RecordDetailView: View {
    let record: HikeRecord

    @State private var tile: GSITile = .standard
    @State private var points: [TrackPoint] = []

    var body: some View {
        GSIMapView(tile: tile, track: points, fitsTrack: true)
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .bottom) { statsBar }
            .navigationTitle(record.title)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                // 軌跡の展開は JSON のデコードを伴うので、画面表示後に行う。
                points = record.points
            }
    }

    private var statsBar: some View {
        HStack(spacing: 0) {
            metric("距離", record.statistics.distanceText)
            metric("のぼり", record.statistics.elevationGainText)
            metric("くだり", record.statistics.elevationLossText)
            metric("時間", record.statistics.elapsedText)
        }
        .padding(.vertical, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
