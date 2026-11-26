import MapKit
import SwiftUI

/// 下山後に寄る場所を探す画面。
struct PostHikeSpotsView: View {
    let plan: HikePlan

    @Environment(\.dismiss) private var dismiss
    @State private var spots: [PostHikeSpot] = []
    @State private var selectedCategories: Set<PostHikeCategory> = [.onsen, .restaurant]
    @State private var isSearching = false

    private var shown: [PostHikeSpot] {
        spots.filter { selectedCategories.contains($0.category) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if plan.trailheadCoordinate == nil {
                    // 山頂で代用すると、車で行けない場所の周りを探してしまう。
                    EmptyStateView(
                        title: "先に登山口を決めてください",
                        message: "下山後に寄る場所は、車を停める登山口の周りから探します。",
                        systemImage: "parkingsign.circle"
                    )
                } else {
                    content
                }
            }
            .navigationTitle("下山後に寄る")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task { await search() }
        }
    }

    @ViewBuilder
    private var content: some View {
        List {
            Section {
                ForEach(PostHikeCategory.allCases) { category in
                    Toggle(isOn: binding(for: category)) {
                        Label(category.label, systemImage: category.symbolName)
                    }
                    .font(.subheadline)
                }
            }

            if isSearching {
                Section {
                    HStack {
                        ProgressView()
                        Text("探しています…").foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                ForEach(shown) { spot in
                    row(spot)
                }
            } header: {
                Text(isSearching ? "" : "\(shown.count) 件")
            } footer: {
                // 太字は ** で書かず、Text をつないで指定する。
                // ** は「。」の直後で閉じると Markdown が閉じ記号とみなさず、
                // 記号がそのまま画面に出てしまう（実際に起きた）。日本語の文ではよく当たる。
                Text("登山口から近い順に並べています。")
                    + Text("営業時間・料金・定休日は地図サービスから取得できません。").bold()
                    + Text("行く前に公式サイトでご確認ください。")
            }
        }
        .overlay {
            if !isSearching, shown.isEmpty {
                EmptyStateView(
                    title: "見つかりませんでした",
                    message: "この登山口の周り15kmには、選んだ種類の場所が登録されていないようです。",
                    systemImage: "mappin.slash"
                )
            }
        }
    }

    private func row(_ spot: PostHikeSpot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: spot.category.symbolName)
                    .font(.caption)
                    .foregroundStyle(Color.brandGreen)
                Text(spot.name)
                    .font(.body.weight(.medium))
            }

            Text(spot.distanceText)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Button {
                    spot.mapItem.openInMaps()
                } label: {
                    Label("地図で開く", systemImage: "map")
                }

                if let url = spot.url {
                    Link(destination: url) {
                        Label("サイト", systemImage: "safari")
                    }
                }
            }
            .font(.caption)
            .buttonStyle(.plain)
            .tint(Color.brandGreen)
        }
        .padding(.vertical, 3)
    }

    private func binding(for category: PostHikeCategory) -> Binding<Bool> {
        Binding(
            get: { selectedCategories.contains(category) },
            set: { isOn in
                if isOn {
                    selectedCategories.insert(category)
                } else {
                    selectedCategories.remove(category)
                }
                Task { await search() }
            }
        )
    }

    private func search() async {
        guard let trailhead = plan.trailheadCoordinate else { return }
        // すでに取れている種類は探し直さない。
        let missing = selectedCategories.filter { category in
            !spots.contains { $0.category == category }
        }
        guard !missing.isEmpty else { return }

        isSearching = true
        defer { isSearching = false }

        let found = await PostHikeSpotService.search(
            near: trailhead,
            categories: Array(missing)
        )
        let existing = Set(spots.map(\.id))
        spots.append(contentsOf: found.filter { !existing.contains($0.id) })
        spots.sort { $0.distanceFromTrailhead < $1.distanceFromTrailhead }
    }
}
