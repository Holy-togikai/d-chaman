import CoreLocation
import MapKit

/// 1つの山を表すデータ。
struct Mountain: Identifiable, Hashable, Codable {
    /// 一意なID。いまは山名をそのまま使っています。
    var id: String { name }

    /// 山名（例: 富士山）
    let name: String
    /// 読みがな。検索でひらがな入力に対応するために持っています。
    let kana: String
    /// 標高（メートル）
    let elevation: Int
    /// 所在する都道府県。複数県にまたがる山があるので配列です。
    let prefectures: [String]
    let latitude: Double
    let longitude: Double
    /// 日本百名山かどうか。
    let isHyakumeizan: Bool

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// 「山梨県・静岡県」のように表示するための文字列。
    var prefectureText: String {
        prefectures.joined(separator: "・")
    }

    /// 検索語に一致するか。山名・かな・都道府県のどれかに含まれていればヒット。
    func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        return name.contains(trimmed)
            || kana.contains(trimmed)
            || prefectures.contains { $0.contains(trimmed) }
    }
}

/// 地図上のピン。MapKit に渡すため、クラスかつ `MKAnnotation` である必要があります。
final class MountainAnnotation: NSObject, MKAnnotation {
    let mountain: Mountain

    init(mountain: Mountain) {
        self.mountain = mountain
    }

    var coordinate: CLLocationCoordinate2D { mountain.coordinate }
    var title: String? { mountain.name }
    var subtitle: String? { "\(mountain.elevation)m ／ \(mountain.prefectureText)" }
}
