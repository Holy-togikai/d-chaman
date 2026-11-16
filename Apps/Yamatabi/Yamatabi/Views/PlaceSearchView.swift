import MapKit
import SwiftUI

/// 住所や地名から場所を探す。出発地（自宅など）の指定に使います。
struct PlaceSearchView: View {
    /// 検索の優先範囲。登山口の近くを優先しても困るので、全国を対象にします。
    let center: CLLocationCoordinate2D
    let onSelect: (String, CLLocationCoordinate2D) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if isSearching {
                    HStack { ProgressView(); Text("検索中…").foregroundStyle(.secondary) }
                }
                if let errorMessage {
                    Text(errorMessage).font(.callout).foregroundStyle(.secondary)
                }
                ForEach(results, id: \.self) { item in
                    Button {
                        guard let coordinate = item.placemark.location?.coordinate else { return }
                        onSelect(displayName(for: item), coordinate)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(displayName(for: item))
                                .font(.body.weight(.medium))
                            if let address = addressText(for: item) {
                                Text(address).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(.primary)
                }
            }
            .searchable(text: $query, prompt: "住所・駅名・施設名")
            .onSubmit(of: .search) { Task { await search() } }
            .navigationTitle("出発地を探す")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .overlay {
                if results.isEmpty, !isSearching, errorMessage == nil {
                    EmptyStateView(
                        title: "出発地を検索",
                        message: "自宅の住所や最寄り駅などを入力して、検索キーを押してください。",
                        systemImage: "house"
                    )
                }
            }
        }
    }

    private func displayName(for item: MKMapItem) -> String {
        item.name ?? item.placemark.name ?? "名称不明"
    }

    private func addressText(for item: MKMapItem) -> String? {
        let placemark = item.placemark
        let parts = [
            placemark.administrativeArea,
            placemark.locality,
            placemark.subLocality,
            placemark.thoroughfare
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined()
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed

        do {
            let response = try await MKLocalSearch(request: request).start()
            results = response.mapItems
            if results.isEmpty {
                errorMessage = "見つかりませんでした。別の言い方でお試しください。"
            }
        } catch {
            errorMessage = "検索できませんでした。通信状況をご確認ください。"
        }
    }
}
