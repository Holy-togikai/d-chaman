import CoreLocation
import MapKit

/// 車での移動の見積もり。
struct DriveEstimate: Equatable {
    let travelTime: TimeInterval
    /// 総走行距離（メートル）
    let distance: Double
    /// 有料道路を通るか。
    let usesTolls: Bool
    /// 高速道路を走ると推定した距離（メートル）。料金の概算に使います。
    let estimatedHighwayDistance: Double
    /// 通過すると推定される高速道路の名前。
    let highwayNames: [String]

    var distanceText: String {
        String(format: "%.1f km", distance / 1000)
    }

    var travelTimeText: String {
        let minutes = Int(travelTime / 60)
        return minutes >= 60 ? "\(minutes / 60)時間\(minutes % 60)分" : "\(minutes)分"
    }
}

/// 高速道路料金の概算。
///
/// NEXCO は料金を取得できる公開APIを提供していないため、距離から見積もっています。
/// **割引（深夜・休日・ETC）や大都市近郊区間の割増は反映されません。**
/// 車種は普通車を基準に、軽自動車・中型車を倍率で近似しています。
/// 正確な金額は「ドラぷら」等で確認してください。
struct TollEstimate: Equatable {
    let amount: Int
    let distance: Double
    /// 利用者が自分で調べて入れた金額か。概算とは区別して表示します。
    let isManual: Bool

    /// ドラぷら等で調べた実際の金額を入れる場合。
    init(manualAmount: Int) {
        amount = manualAmount
        distance = 0
        isManual = true
    }

    /// 普通車の対距離料金（円/km、消費税込み）。
    static let ratePerKilometer = 24.6
    /// 1回の利用ごとに加算される固定額（円）。
    static let terminalCharge = 150.0

    init(highwayDistance: Double, vehicle: VehicleClass = .standard) {
        distance = highwayDistance
        isManual = false
        guard highwayDistance > 0 else {
            amount = 0
            return
        }
        let raw = (highwayDistance / 1000 * Self.ratePerKilometer + Self.terminalCharge)
            * 1.1 * vehicle.tollMultiplier
        // 実際の料金は50円単位なので、それに合わせて丸める。
        amount = Int((raw / 50).rounded() * 50)
    }

    var amountText: String {
        "約 \(amount.formatted(.number.grouping(.automatic))) 円"
    }

    /// ドラぷらの料金検索を開くURL。正確な金額はここで確認してもらいます。
    static let driveplazaURL = URL(string: "https://www.driveplaza.com/dp/SearchTop")!
}

enum RouteService {

    enum Failure: LocalizedError {
        case noRoute

        var errorDescription: String? {
            switch self {
            case .noRoute: "経路が見つかりませんでした。出発地と登山口をご確認ください。"
            }
        }
    }

    /// 高速道路の判定に使う語。MapKit の案内文に含まれる道路名から拾います。
    private static let highwayKeywords = ["自動車道", "高速道路", "有料道路", "道路公団", "エクスプレスウェイ"]

    static func drive(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> DriveEstimate {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile

        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else { throw Failure.noRoute }

        // MapKit は料金を教えてくれないので、案内文から高速道路の区間を拾って距離を足す。
        // 正確な区間分割ではないため、あくまで概算の材料。
        var highwayDistance: Double = 0
        var names: Set<String> = []
        for step in route.steps {
            let text = step.instructions
            guard let keyword = highwayKeywords.first(where: { text.contains($0) }) else { continue }
            highwayDistance += step.distance
            if let name = highwayName(in: text, keyword: keyword) {
                names.insert(name)
            }
        }

        return DriveEstimate(
            travelTime: route.expectedTravelTime,
            distance: route.distance,
            usesTolls: route.hasTolls,
            estimatedHighwayDistance: highwayDistance,
            highwayNames: names.sorted()
        )
    }

    /// 「中央自動車道に入ります」のような案内文から道路名を切り出す。
    private static func highwayName(in text: String, keyword: String) -> String? {
        guard let range = text.range(of: keyword) else { return nil }
        // キーワードの手前にある名前の部分を、助詞や記号の手前まで遡って取り出す。
        let prefix = text[text.startIndex..<range.lowerBound]
        let separators = CharacterSet(charactersIn: "、。 　「」をにでへとはがのり")
        let name = prefix.unicodeScalars.reversed()
            .prefix { !separators.contains($0) }
            .reversed()
            .map(Character.init)
        let full = String(name) + keyword
        return full.count > keyword.count ? full : nil
    }
}
