import SwiftData
import SwiftUI

/// 山の探し方。目的によって入口を分けています。
enum MountainFinderMode: String, CaseIterable, Identifiable {
    case map
    case hyakumeizan
    case keyword
    case history

    var id: String { rawValue }

    var label: String {
        switch self {
        case .map: "地図"
        case .hyakumeizan: "百名山"
        case .keyword: "検索"
        case .history: "履歴"
        }
    }

    var symbolName: String {
        switch self {
        case .map: "map"
        case .hyakumeizan: "star"
        case .keyword: "magnifyingglass"
        case .history: "clock.arrow.circlepath"
        }
    }
}

/// 山を選ぶ画面。地図・百名山・キーワード・履歴の4つの入口を持ちます。
///
/// 記録の開始と登山計画の作成の両方から使われるため、選ばれた山を返すだけの役割に留めています。
struct MountainFinderView: View {
    let mountains: [Mountain]
    let onSelect: (Mountain) -> Void

    @State private var mode: MountainFinderMode = .keyword
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("探し方", selection: $mode) {
                    ForEach(MountainFinderMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.symbolName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                content
            }
            .navigationTitle("山を探す")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .map:
            MountainMapPicker(mountains: mountains, onSelect: select)
        case .hyakumeizan:
            HyakumeizanList(onSelect: select)
        case .keyword:
            MountainKeywordList(mountains: mountains, onSelect: select)
        case .history:
            MountainHistoryList(onSelect: select)
        }
    }

    private func select(_ mountain: Mountain) {
        onSelect(mountain)
        dismiss()
    }
}

// MARK: - 地図から探す

/// 地図を動かして、見えているピンから選ぶ。
///
/// 「この辺りの山」という探し方は一覧ではできないため、地図を入口として用意しています。
private struct MountainMapPicker: View {
    let mountains: [Mountain]
    let onSelect: (Mountain) -> Void

    @State private var tappedMountain: Mountain?

    var body: some View {
        GSIMapView(
            tile: .standard,
            annotations: mountains.map(MountainAnnotation.init),
            onSelect: { tappedMountain = $0.mountain }
        )
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .top) {
            Text("ピンをタップすると山の名前が出ます。ⓘ を押すと決定します。")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 6)
        }
        .onChange(of: tappedMountain) { _, mountain in
            guard let mountain else { return }
            onSelect(mountain)
        }
    }
}

// MARK: - 百名山から探す

/// 日本百名山の100座。深田久弥の呼称で並べます。
private struct HyakumeizanList: View {
    let onSelect: (Mountain) -> Void

    @State private var query = ""

    private var results: [Mountain] {
        MountainData.hyakumeizan.filter { $0.matches(query) }
    }

    var body: some View {
        List {
            Section {
                ForEach(results) { mountain in
                    Button { onSelect(mountain) } label: { row(mountain) }
                        .tint(.primary)
                }
            } header: {
                Text("\(results.count) 座")
            } footer: {
                Text("日本百名山（深田久弥）の100座です。"
                     + "地理院の登録名と呼び名が違う山は、下に登録名を添えています。")
            }
        }
        .searchable(text: $query, prompt: "山名・ふりがな・都道府県")
        .overlay {
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private func row(_ mountain: Mountain) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mountain.hyakumeizanDisplayName)
                    .font(.body.weight(.medium))
                Text(mountain.prefectureText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let subtitle = mountain.hyakumeizanSubtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text("\(mountain.elevation)m")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - キーワードで探す

/// 山名・ふりがな・都道府県で絞り込む。標高の高い順に並びます。
private struct MountainKeywordList: View {
    let mountains: [Mountain]
    let onSelect: (Mountain) -> Void

    @State private var query = ""
    @State private var onlyHyakumeizan = false

    private var results: [Mountain] {
        // データは標高の高い順に並んだ状態で読み込んでいるので、並べ替えは不要。
        mountains.filter { mountain in
            (!onlyHyakumeizan || mountain.isHyakumeizan) && mountain.matches(query)
        }
    }

    var body: some View {
        List {
            Section {
                Toggle("日本百名山だけ", isOn: $onlyHyakumeizan)
                    .font(.subheadline)
            }

            Section {
                ForEach(results) { mountain in
                    Button { onSelect(mountain) } label: { MountainRow(mountain: mountain) }
                        .tint(.primary)
                }
            } header: {
                Text("\(results.count) 件")
            } footer: {
                attributionFooter
            }
        }
        .searchable(text: $query, prompt: "山名・ふりがな・都道府県")
        .overlay {
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    /// 山岳データの出典。利用条件として明示が必要です。消さないでください。
    private var attributionFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("山岳データ出典")
            Link(
                "国土地理院「日本の主な山岳標高」",
                destination: URL(
                    string: "https://www.gsi.go.jp/kihonjohochousa/kihonjohochousa41139.html"
                )!
            )
        }
        .font(.caption2)
        .padding(.top, 8)
    }
}

// MARK: - 履歴から探す

/// 過去に登った山。登山記録に残した山から引き直します。
private struct MountainHistoryList: View {
    let onSelect: (Mountain) -> Void

    @Query(sort: \HikeRecord.startedAt, order: .reverse) private var records: [HikeRecord]

    /// 履歴の1行ぶん。
    private struct Visit: Identifiable {
        let mountain: Mountain
        let lastClimbed: Date
        let count: Int

        var id: String { mountain.id }
    }

    /// 同じ山を何度も出さないよう、新しい記録を優先して重複を落とします。
    private var visited: [Visit] {
        var order: [String] = []
        var lastClimbed: [String: Date] = [:]
        var counts: [String: Int] = [:]

        for record in records {
            guard let identifier = record.mountainID else { continue }
            if lastClimbed[identifier] == nil {
                order.append(identifier)
                lastClimbed[identifier] = record.startedAt
            }
            counts[identifier, default: 0] += 1
        }

        return order.compactMap { identifier in
            guard let mountain = MountainData.mountain(id: identifier),
                  let date = lastClimbed[identifier] else { return nil }
            return Visit(mountain: mountain, lastClimbed: date, count: counts[identifier] ?? 1)
        }
    }

    var body: some View {
        List {
            ForEach(visited) { entry in
                Button {
                    onSelect(entry.mountain)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        MountainRow(mountain: entry.mountain)
                        HStack(spacing: 10) {
                            Label(
                                entry.lastClimbed.formatted(date: .abbreviated, time: .omitted),
                                systemImage: "clock"
                            )
                            if entry.count > 1 {
                                Label("\(entry.count) 回", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .tint(.primary)
            }
        }
        .overlay {
            if visited.isEmpty {
                ContentUnavailableView(
                    "登った山がまだありません",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("山を選んで記録を取ると、ここに並びます。")
                )
            }
        }
    }
}

// MARK: - 共通の行

/// 一覧で使う山の1行。
struct MountainRow: View {
    let mountain: Mountain

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(mountain.displayName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
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
}
