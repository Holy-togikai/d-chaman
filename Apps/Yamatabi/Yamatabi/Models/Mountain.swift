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
    /// 深田久弥の呼称。地理院の登録名と異なることがあります（例: 白根山 → 日光白根山）。
    let hyakumeizanName: String?
    /// 百名山1座を代表する地点か。一覧をちょうど100件で出すために使います。
    let isHyakumeizanPeak: Bool

    /// 画面に出す名前。副峰は「蔵王山（熊野岳）」のように括弧を添えます。
    var displayName: String {
        guard let peak else { return name }
        return "\(name)（\(peak)）"
    }

    /// 百名山の一覧で使う名前。深田の呼称を優先します。
    /// 「日光白根山」を探している人に「白根山」とだけ出すと、草津白根山と見分けが付かないため。
    var hyakumeizanDisplayName: String {
        hyakumeizanName ?? displayName
    }

    /// 深田の呼称が地理院の登録名と違う場合に、元の名前を添えるための文字列。
    var hyakumeizanSubtitle: String? {
        guard let hyakumeizanName, hyakumeizanName != name else { return nil }
        return "地理院の登録名: \(displayName)"
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
            || (hyakumeizanName?.contains(trimmed) ?? false)
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
