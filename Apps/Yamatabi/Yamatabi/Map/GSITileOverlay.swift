import MapKit
import UIKit

/// 地理院タイルを、保存したもの → 配信元 → 粗いズームの拡大、の順で探して出すオーバーレイ。
///
/// 保存したものを先に使うのは、電波の無い山中で表示するためと、国土地理院のサーバーへの
/// 負荷を減らすためです（回答で負荷への配慮を求められています）。
final class GSITileOverlay: MKTileOverlay {
    let tile: GSITile
    private let store: OfflineTileStore

    /// 配信元を待つ上限。既定の60秒だと、電波が弱い山中で地図がしばらく真っ白になります。
    /// 早く諦めて、保存した粗いタイルの拡大に切り替えるほうが役に立ちます。
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        // 同時に取りに行く数を抑える。地図を動かすたびに大量に投げないように。
        configuration.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: configuration)
    }()

    /// 粗いズームを何段まで遡って拡大するか。
    /// 4段（16倍）を超えると、拡大しても文字や道が読めず、役に立たないためです。
    static let maximumOverzoom = 4

    init(tile: GSITile, store: OfflineTileStore) {
        self.tile = tile
        self.store = store
        super.init(urlTemplate: nil)
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        tile.url(z: path.z, x: path.x, y: path.y)
            ?? URL(string: "https://maps.gsi.go.jp/development/ichiran.html")!
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let key = TileKey(tile: tile, z: path.z, x: path.x, y: path.y)

        if let saved = store.data(for: key) {
            result(saved, nil)
            return
        }

        let request = URLRequest(url: url(forTilePath: path))
        Self.session.dataTask(with: request) { [store] data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let data, error == nil, status == 200 {
                result(data, nil)
                return
            }
            // 届かなかったとき。保存してある粗いタイルを拡大して、少なくとも地形は見せる。
            if let fallback = Self.overzoomed(key: key, store: store) {
                result(fallback, nil)
            } else {
                result(nil, error ?? URLError(.resourceUnavailable))
            }
        }.resume()
    }

    /// 保存した粗いズームのタイルから、該当する部分を切り出して拡大する。
    ///
    /// 表示のためにその場で作るだけで、保存はしません。保存すると「別の成果物を生成」に
    /// 当たるおそれがあり、国土地理院の回答にある私的利用の範囲を外れかねないためです。
    static func overzoomed(key: TileKey, store: OfflineTileStore) -> Data? {
        for levels in 1...maximumOverzoom {
            guard let parent = key.ancestor(levelsUp: levels),
                  let data = store.data(for: parent),
                  let image = UIImage(data: data)?.cgImage else { continue }

            let scale = 1 << levels
            let side = image.width / scale
            guard side > 0 else { continue }
            let offsetX = (key.x - (parent.x << levels)) * side
            let offsetY = (key.y - (parent.y << levels)) * side
            guard let piece = image.cropping(
                to: CGRect(x: offsetX, y: offsetY, width: side, height: side)
            ) else { continue }

            let size = CGSize(width: 256, height: 256)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
                context.cgContext.interpolationQuality = .none
                UIImage(cgImage: piece).draw(in: CGRect(origin: .zero, size: size))
            }
            return rendered.pngData()
        }
        return nil
    }
}
