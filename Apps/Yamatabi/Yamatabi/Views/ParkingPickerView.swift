import MapKit
import SwiftUI

/// 登山口を決める画面。
///
/// 周辺の駐車場を一覧から選ぶのが基本ですが、登山口に駐車場が登録されていない山も多いため、
/// 地図を長押しして自分で指定する逃げ道を必ず用意しています。
struct ParkingPickerView: View {
    let summit: CLLocationCoordinate2D
    let onSelect: (ParkingSpot) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var spots: [ParkingSpot] = []
    @State private var isSearching = true
    @State private var errorMessage: String?
    @State private var customCoordinate: CLLocationCoordinate2D?

    var body: some View {
        NavigationStack {
            Group {
                if isSearching {
                    ProgressView("駐車場を探しています…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    content
                }
            }
            .navigationTitle("登山口を選ぶ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task { await search() }
        }
    }

    private var content: some View {
        List {
            Section {
                mapPicker
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
            } footer: {
                Text("地図を長押しすると、その場所を登山口に指定できます。"
                     + "登山口に駐車場が登録されていない山では、こちらを使ってください。")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).font(.callout).foregroundStyle(.secondary)
                }
            }

            if !spots.isEmpty {
                Section("周辺の駐車場（山頂に近い順）") {
                    ForEach(spots) { spot in
                        Button {
                            onSelect(spot)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(spot.name)
                                    .font(.body.weight(.medium))
                                Text(spot.distanceText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(.primary)
                    }
                }
            }
        }
    }

    private var mapPicker: some View {
        ZStack(alignment: .bottom) {
            GSIMapView(
                tile: .standard,
                initialCenter: summit,
                onLongPress: { coordinate in
                    customCoordinate = coordinate
                }
            )

            if let customCoordinate {
                Button {
                    onSelect(
                        ParkingSpot(
                            id: "custom-\(customCoordinate.latitude),\(customCoordinate.longitude)",
                            name: "指定した登山口",
                            coordinate: customCoordinate,
                            distanceFromSummit: CLLocation(
                                latitude: customCoordinate.latitude,
                                longitude: customCoordinate.longitude
                            ).distance(
                                from: CLLocation(latitude: summit.latitude, longitude: summit.longitude)
                            ),
                            phoneNumber: nil,
                            mapItem: MKMapItem(placemark: MKPlacemark(coordinate: customCoordinate))
                        )
                    )
                    dismiss()
                } label: {
                    Label("この地点を登山口にする", systemImage: "mappin.and.ellipse")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.brandGreen, in: Capsule())
                        .foregroundStyle(.white)
                }
                .padding(.bottom, 12)
            }
        }
    }

    private func search() async {
        isSearching = true
        defer { isSearching = false }
        do {
            spots = try await ParkingService.search(near: summit)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
