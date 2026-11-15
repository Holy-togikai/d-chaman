import CoreLocation
import MapKit

/// 登山口の駐車場の候補。
struct ParkingSpot: Identifiable, Equatable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    /// 山頂からの直線距離（メートル）。近いほど登山口に近い可能性が高い。
    let distanceFromSummit: Double
    /// 電話番号。詳細を問い合わせたいときのため。
    let phoneNumber: String?
    let mapItem: MKMapItem

    static func == (lhs: ParkingSpot, rhs: ParkingSpot) -> Bool { lhs.id == rhs.id }

    var distanceText: String {
        distanceFromSummit >= 1000
            ? String(format: "山頂から %.1f km", distanceFromSummit / 1000)
            : String(format: "山頂から %.0f m", distanceFromSummit)
    }
}

/// 山の周辺から駐車場を探す。
///
/// ⚠️ **料金と駐車台数は取得できません。** Apple の地図検索はこれらを提供しておらず、
/// 日本の登山口駐車場について、料金・台数まで揃った公開データは存在しません。
/// これらは計画ごとに手で記録してもらう前提にしています。
enum ParkingService {

    enum Failure: LocalizedError {
        case notFound

        var errorDescription: String? {
            switch self {
            case .notFound:
                "周辺に駐車場が見つかりませんでした。地図を長押しして登山口を指定してください。"
            }
        }
    }

    /// 山頂を中心に駐車場を探す。
    ///
    /// - Parameter radius: 検索範囲（メートル）。登山口は山頂からかなり離れることがあるため、
    ///   既定では広めに取っています。
    static func search(
        near summit: CLLocationCoordinate2D,
        radius: CLLocationDistance = 8000
    ) async throws -> [ParkingSpot] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "駐車場"
        request.region = MKCoordinateRegion(
            center: summit,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )
        if #available(iOS 18.0, *) {
            request.regionPriority = .required
        }

        let response = try await MKLocalSearch(request: request).start()
        let summitLocation = CLLocation(latitude: summit.latitude, longitude: summit.longitude)

        let spots = response.mapItems.compactMap { item -> ParkingSpot? in
            guard let coordinate = item.placemark.location?.coordinate else { return nil }
            let distance = CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ).distance(from: summitLocation)

            return ParkingSpot(
                id: "\(coordinate.latitude),\(coordinate.longitude)",
                name: item.name ?? "駐車場",
                coordinate: coordinate,
                distanceFromSummit: distance,
                phoneNumber: item.phoneNumber,
                mapItem: item
            )
        }
        // 山頂に近い順。登山口に近い駐車場が上に来るようにする。
        .sorted { $0.distanceFromSummit < $1.distanceFromSummit }

        guard !spots.isEmpty else { throw Failure.notFound }
        return spots
    }
}
