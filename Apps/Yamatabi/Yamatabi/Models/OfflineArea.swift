import Foundation
import SwiftData

/// 保存した地図の範囲。タイルそのものは `OfflineTileStore` に置き、ここには範囲だけを持ちます。
@Model
final class OfflineArea {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var tileRaw: String = GSITile.standard.rawValue

    var minLatitude: Double = 0
    var maxLatitude: Double = 0
    var minLongitude: Double = 0
    var maxLongitude: Double = 0
    var minZoom: Int = OfflineMapPolicy.zooms.lowerBound
    var maxZoom: Int = OfflineMapPolicy.zooms.upperBound

    /// 範囲を覆うタイルの枚数（見積もり）。
    var tileCount: Int = 0
    /// 実際に保存できた枚数。海の上などは配信が無いので、見積もりより少なくなります。
    var savedTileCount: Int = 0
    /// 最後まで取り終えたか。途中で止めたときは false のまま残し、続きから取れるようにします。
    var isComplete: Bool = false

    init(name: String, tile: GSITile, box: GeoBox, zooms: ClosedRange<Int>) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.tileRaw = tile.rawValue
        self.minLatitude = box.minLatitude
        self.maxLatitude = box.maxLatitude
        self.minLongitude = box.minLongitude
        self.maxLongitude = box.maxLongitude
        self.minZoom = zooms.lowerBound
        self.maxZoom = zooms.upperBound
        self.tileCount = TileMath.count(of: box, zooms: zooms)
    }

    var tile: GSITile { GSITile(rawValue: tileRaw) ?? .standard }

    var box: GeoBox {
        GeoBox(
            minLatitude: minLatitude,
            maxLatitude: maxLatitude,
            minLongitude: minLongitude,
            maxLongitude: maxLongitude
        )
    }

    var zooms: ClosedRange<Int> { minZoom...maxZoom }

    var keys: [TileKey] { TileMath.keys(of: box, zooms: zooms, tile: tile) }
}

/// まとめて保存するときの決まりごと。
///
/// 国土地理院から「サーバの負荷軽減への配慮」を求められており、過大な負荷には
/// 予告なく遮断されることがあると回答されています（決定記録 0001）。
/// 遮断されると、この端末だけでなく、このアプリの利用者全員の地図が出なくなります。
/// そのため、量と速さの両方に上限を設けています。
enum OfflineMapPolicy {
    /// 保存するズームの幅。
    ///
    /// 16 で登山道と等高線が読めます。17・18 は保存せず、16 を拡大して見せます。
    /// 17 まで保存すると枚数が4倍になり、得られるものに比べて負荷が大きすぎるためです。
    static let zooms = 10...16

    /// 1回に保存できる枚数の上限。
    ///
    /// 山1つ（10km四方ほど）をズーム16まで保存すると約600枚です。その数倍の余裕を見ています。
    static let maximumTilesPerArea = 3000

    /// 同時に取りに行く数。
    static let concurrentRequests = 2

    /// 1枚取るごとに空ける間（秒）。
    static let intervalBetweenRequests: TimeInterval = 0.1

    /// 1枚あたりの大きさの目安（バイト）。保存する前に容量を見積もるのに使います。
    ///
    /// 北岳の周り（標準地図590枚）で実測すると 20.1MB、1枚あたり約34KBだった。
    /// 山の地図は等高線が混むため、平地より重い。少なく見積もると空き容量を見誤るので、多めに取る。
    /// 写真は実測していない。JPEG で標準地図より重くなる前提で置いている。
    static func estimatedBytesPerTile(_ tile: GSITile) -> Int {
        switch tile {
        case .standard, .pale: 35_000
        case .photo: 45_000
        }
    }

    /// 残す保存範囲。消すときに、重なりを調べるのに使います。
    struct KeptArea {
        let tile: GSITile
        let box: GeoBox
        let zooms: ClosedRange<Int>
    }

    /// 消してよいタイル。他の保存範囲と重なっているものは残します。
    static func removableKeys(of keys: [TileKey], keeping others: [KeptArea]) -> [TileKey] {
        keys.filter { key in
            !others.contains { other in
                other.tile == key.tile && TileMath.covers(other.box, zooms: other.zooms, key: key)
            }
        }
    }
}
