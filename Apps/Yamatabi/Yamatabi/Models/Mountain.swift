import CoreLocation
import MapKit

/// 1つの山（正確には1つの山頂）を表すデータ。
///
/// 出典は国土地理院「日本の主な山岳標高」。同じ山に複数の山頂がある場合
/// （蔵王山の熊野岳・刈田岳など）は、山頂ごとに1件ずつ存在します。
struct Mountain: Identifiable, Hashable, Codable {
    /// 国土地理院の索引番号。「204-1」のように、副峰には枝番が付きます。
    let id: String
    /// 山名（例: 蔵王山）
    let name: String
    /// 山頂名。副峰にだけ入ります（例: 熊野岳）。
    let peak: String?
    /// 検索用のよみ。別名も含めて空白区切りでつながっています。
    let kana: String
    /// 標高（メートル）
    let elevation: Int
    /// 所在する都道府県。県境の山は複数入ります。
    let prefectures: [String]
    let latitude: Double
    let longitude: Double
    /// 日本百名山に数えられる山か。副峰にも同じ値が入ります。
    let isHyakumeizan: Bool

    /// 画面に出す名前。副峰は「蔵王山（熊野岳）」のように括弧を添えます。
    var displayName: String {
        guard let peak else { return name }
        return "\(name)（\(peak)）"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// 「山梨県・静岡県」のように表示するための文字列。
    var prefectureText: String {
        prefectures.joined(separator: "・")
    }

    /// 検索語に一致するか。山名・山頂名・よみ・都道府県のどれかに含まれていればヒット。
    func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        return name.contains(trimmed)
            || (peak?.contains(trimmed) ?? false)
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
    var title: String? { mountain.displayName }
    var subtitle: String? { "\(mountain.elevation)m ／ \(mountain.prefectureText)" }
}
