import MapKit

/// 国土地理院が配信している地図タイルの種類。
///
/// 利用条件: リアルタイムに読み込んで表示する場合は、出典を明示すれば申請不要で利用できます。
/// 端末内に保存する（オフライン化）場合は測量法に基づく申請が別途必要になる可能性があるため、
/// 現段階ではオンライン表示のみに留めています。
/// 参照: https://maps.gsi.go.jp/development/ichiran.html
enum GSITile: String, CaseIterable, Identifiable {
    /// 標準地図。登山道・等高線が載った、いちばん基本の地図。
    case standard
    /// 淡色地図。色が薄く、上に軌跡を重ねたときに見やすい。
    case pale
    /// 写真（空中写真・衛星画像）。
    case photo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: "標準地図"
        case .pale: "淡色地図"
        case .photo: "写真"
        }
    }

    /// タイル配信URLのテンプレート。`{z}` `{x}` `{y}` は MapKit が座標に置き換えます。
    var urlTemplate: String {
        switch self {
        case .standard: "https://cyberjapandata.gsi.go.jp/xyz/std/{z}/{x}/{y}.png"
        case .pale: "https://cyberjapandata.gsi.go.jp/xyz/pale/{z}/{x}/{y}.png"
        case .photo: "https://cyberjapandata.gsi.go.jp/xyz/seamlessphoto/{z}/{x}/{y}.jpg"
        }
    }

    /// この種類で配信されている最大ズームレベル。これを超えると404が返ります。
    var maximumZ: Int {
        switch self {
        case .standard, .pale: 18
        case .photo: 18
        }
    }

    /// MapKit に渡すオーバーレイを組み立てる。
    func makeOverlay() -> MKTileOverlay {
        let overlay = MKTileOverlay(urlTemplate: urlTemplate)
        // Apple標準の地図を完全に隠して、地理院タイルだけを表示する。
        overlay.canReplaceMapContent = true
        overlay.maximumZ = maximumZ
        return overlay
    }
}
