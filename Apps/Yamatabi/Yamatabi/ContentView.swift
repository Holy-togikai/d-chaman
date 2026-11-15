import SwiftUI

struct ContentView: View {
    /// 表示中のタイル種別。
    @State private var tile: GSITile = .standard
    /// 選択中の山。
    @State private var selected: Mountain?
    /// 山を探すシートを出しているか。
    @State private var isSearching = false

    private let mountains = MountainData.all

    var body: some View {
        GSIMapView(
            tile: tile,
            annotations: mountains.map(MountainAnnotation.init),
            focused: selected,
            onSelect: { selected = $0.mountain }
        )
        .ignoresSafeArea()
        // 操作バーと出典表示は overlay で重ねる。
        // ZStack に全画面の子を並べると、上に乗った子がタップを吸ってしまうため。
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottomLeading) {
            attribution
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .sheet(isPresented: $isSearching) {
            MountainListView(mountains: mountains) { mountain in
                selected = mountain
                isSearching = false
            }
        }
    }

    /// 画面上部の操作バー。山を探すボタンと、地図の種類切り替え。
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
}
