import MapKit

/// 国土地理院が配信している地図タイルの種類。
///
/// 利用条件: リアルタイムに読み込んで表示する場合は、出典を明示すれば申請不要で利用できます。
/// 端末内への保存も、利用者の私的利用に留まるなら申請不要と国土地理院から回答を得ています
/// （docs/decisions/0001-gsi-offline-tiles.md）。
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

    /// 保存するときの拡張子。配信元と同じ形式のまま、手を加えずに保存します。
    var fileExtension: String {
        switch self {
        case .standard, .pale: "png"
        case .photo: "jpg"
        }
    }

    private var path: String {
        switch self {
        case .standard: "std"
        case .pale: "pale"
        case .photo: "seamlessphoto"
        }
    }

    /// この種類で配信されている最大ズームレベル。これを超えると404が返ります。
    var maximumZ: Int { 18 }

    /// 写真をこのズームより粗く見るときは、標準地図に差し替える。
    ///
    /// 写真のズーム8以下は「世界衛星モザイク画像」で、地理院タイル一覧の備考により
    /// NASA などの長い出所表示を画面に出す必要があります。日本全体を見渡す縮尺で
    /// 写真が要る場面はほぼ無いため、出所表示を増やすより標準地図で見せることにしました。
    static let photoMinimumZ = 9

    /// タイル1枚の配信URL。
    func url(z: Int, x: Int, y: Int) -> URL? {
        if self == .photo, z < Self.photoMinimumZ {
            return GSITile.standard.url(z: z, x: x, y: y)
        }
        return URL(string: "https://cyberjapandata.gsi.go.jp/xyz/\(path)/\(z)/\(x)/\(y).\(fileExtension)")
    }

    /// 「地理院タイル」に加えて出す出所。
    ///
    /// 写真のズーム9〜13は Landsat8 の画像で、地理院タイル一覧の備考がこの表記を求めています。
    /// どのズームを見ているかで出し分けると、出し忘れる隙ができるため、写真のときは常に出します。
    var extraAttribution: String? {
        switch self {
        case .photo:
            "データソース：Landsat8画像（GSI,TSIC,GEO Grid/AIST）, "
                + "Landsat8画像（courtesy of the U.S. Geological Survey）, 海底地形（GEBCO）"
        case .standard, .pale:
            nil
        }
    }

    /// MapKit に渡すオーバーレイを組み立てる。保存したタイルがあれば、そちらを先に使います。
    func makeOverlay(store: OfflineTileStore = .shared) -> MKTileOverlay {
        let overlay = GSITileOverlay(tile: self, store: store)
        // Apple標準の地図を完全に隠して、地理院タイルだけを表示する。
        overlay.canReplaceMapContent = true
        overlay.maximumZ = maximumZ
        return overlay
    }
}
