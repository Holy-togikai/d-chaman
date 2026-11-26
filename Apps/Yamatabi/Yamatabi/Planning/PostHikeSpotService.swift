import CoreLocation
import MapKit

/// 下山後に寄る場所の種類。
enum PostHikeCategory: String, CaseIterable, Identifiable, Codable {
    case onsen
    case restaurant
    case roadsideStation

    var id: String { rawValue }

    var label: String {
        switch self {
        case .onsen: "温泉・日帰り入浴"
        case .restaurant: "食事処"
        case .roadsideStation: "道の駅・物産"
        }
    }

    var symbolName: String {
        switch self {
        case .onsen: "drop.fill"
        case .restaurant: "fork.knife"
        case .roadsideStation: "bag.fill"
        }
    }

    /// 地図検索に投げる言葉。
    ///
    /// 「温泉」だけだと温泉地の地名まで拾うので、入浴施設を指す語を並べています。
    var queries: [String] {
        switch self {
        case .onsen: ["日帰り温泉", "温泉"]
        case .restaurant: ["食事処", "レストラン"]
        case .roadsideStation: ["道の駅"]
        }
    }
}

/// 下山後に寄れる場所。
struct PostHikeSpot: Identifiable, Equatable {
    let id: String
    let name: String
    let category: PostHikeCategory
    let coordinate: CLLocationCoordinate2D
    /// 登山口からの直線距離（メートル）。
    let distanceFromTrailhead: CLLocationDistance
    /// 公式サイト。電話番号は持たない。アプリで見る人はウェブで確かめたいと考え、出さないことにしたため。
    let url: URL?
    let mapItem: MKMapItem

    static func == (lhs: PostHikeSpot, rhs: PostHikeSpot) -> Bool { lhs.id == rhs.id }

    var distanceText: String {
        distanceFromTrailhead >= 1000
            ? String(format: "登山口から %.1f km", distanceFromTrailhead / 1000)
            : String(format: "登山口から %.0f m", distanceFromTrailhead)
    }
}

/// 下山後に寄れる場所を、登山口の周りから探す。
///
/// ⚠️ **営業時間・料金・定休日は取得できません。** Apple の地図検索はこれらを返さず、
/// 日本の入浴施設や食事処について、これらが揃った公開データもありません。
/// 並び順の根拠は登山口からの近さだけです。実際に行く前に、公式サイトで確認してください。
enum PostHikeSpotService {

    /// 探す範囲（メートル）。車で寄る前提なので広めに取ります。
    static let defaultRadius: CLLocationDistance = 15_000

    /// 登山口の周りから探す。
    ///
    /// - Parameter trailhead: 車を停める場所。山頂ではありません。
    ///   下山後に向かう先なので、起点は必ず登山口にします。
    static func search(
        near trailhead: CLLocationCoordinate2D,
        categories: [PostHikeCategory],
        radius: CLLocationDistance = defaultRadius
    ) async -> [PostHikeSpot] {
        var found: [String: PostHikeSpot] = [:]
        let origin = CLLocation(latitude: trailhead.latitude, longitude: trailhead.longitude)

        for category in categories {
            for query in category.queries {
                // 同時に投げると地図サービスに絞られることがあるので、順番に投げる。
                let spots = await search(query: query, category: category, around: trailhead,
                                         radius: radius, origin: origin)
                for spot in spots where found[spot.id] == nil {
                    found[spot.id] = spot
                }
            }
        }

        return found.values.sorted { $0.distanceFromTrailhead < $1.distanceFromTrailhead }
    }

    private static func search(
        query: String,
        category: PostHikeCategory,
        around center: CLLocationCoordinate2D,
        radius: CLLocationDistance,
        origin: CLLocation
    ) async -> [PostHikeSpot] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )

        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }

        return response.mapItems.compactMap { item -> PostHikeSpot? in
            guard let coordinate = item.placemark.location?.coordinate else { return nil }
            let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .distance(from: origin)
            // 指定した範囲は地図サービスへの「希望」でしかなく、遠くの結果も混ざる。
            // 車で寄れる距離に収まらないものは自分で落とす。
            guard distance <= radius else { return nil }

            return PostHikeSpot(
                id: "\(coordinate.latitude),\(coordinate.longitude)",
                name: item.name ?? category.label,
                category: category,
                coordinate: coordinate,
                distanceFromTrailhead: distance,
                url: item.url,
                mapItem: item
            )
        }
    }
}
