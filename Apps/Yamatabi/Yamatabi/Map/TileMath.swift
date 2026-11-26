import CoreLocation
import Foundation

/// タイル1枚の住所。種類・ズーム・横・縦で決まります。
struct TileKey: Hashable {
    let tile: GSITile
    let z: Int
    let x: Int
    let y: Int

    /// ひとつ上（粗い）のズームで、この範囲を含むタイル。
    func ancestor(levelsUp: Int) -> TileKey? {
        guard levelsUp > 0, z - levelsUp >= 0 else { return nil }
        return TileKey(tile: tile, z: z - levelsUp, x: x >> levelsUp, y: y >> levelsUp)
    }
}

/// 緯度経度の四角い範囲。保存する範囲を表すのに使います。
struct GeoBox: Equatable {
    let minLatitude: Double
    let maxLatitude: Double
    let minLongitude: Double
    let maxLongitude: Double
}

/// 地図タイルの番号の計算（Webメルカトル、地理院タイルも同じ方式）。
///
/// 参考: https://maps.gsi.go.jp/development/siyou.html
enum TileMath {

    /// その地点を含むタイルの横番号。
    static func x(longitude: Double, z: Int) -> Int {
        let tilesPerSide = Double(1 << z)
        let value = Int(floor((longitude + 180) / 360 * tilesPerSide))
        return min(max(value, 0), (1 << z) - 1)
    }

    /// その地点を含むタイルの縦番号。北ほど小さくなります。
    static func y(latitude: Double, z: Int) -> Int {
        let tilesPerSide = Double(1 << z)
        let radians = latitude * .pi / 180
        let value = Int(floor((1 - log(tan(radians) + 1 / cos(radians)) / .pi) / 2 * tilesPerSide))
        return min(max(value, 0), (1 << z) - 1)
    }

    /// 範囲を覆うタイルの、横と縦の番号の幅。
    static func range(of box: GeoBox, z: Int) -> (x: ClosedRange<Int>, y: ClosedRange<Int>) {
        let xRange = x(longitude: box.minLongitude, z: z)...x(longitude: box.maxLongitude, z: z)
        // 縦は北が小さいので、最大緯度のほうが小さい番号になる。
        let yRange = y(latitude: box.maxLatitude, z: z)...y(latitude: box.minLatitude, z: z)
        return (xRange, yRange)
    }

    /// 範囲とズームの幅を覆うタイルの枚数。取得する前に量を見積もるのに使います。
    static func count(of box: GeoBox, zooms: ClosedRange<Int>) -> Int {
        zooms.reduce(0) { total, z in
            let (xs, ys) = range(of: box, z: z)
            return total + xs.count * ys.count
        }
    }

    /// 範囲とズームの幅を覆うタイルをすべて並べる。粗いズームから順に返します。
    static func keys(of box: GeoBox, zooms: ClosedRange<Int>, tile: GSITile) -> [TileKey] {
        var keys: [TileKey] = []
        for z in zooms {
            let (xs, ys) = range(of: box, z: z)
            for x in xs {
                for y in ys {
                    keys.append(TileKey(tile: tile, z: z, x: x, y: y))
                }
            }
        }
        return keys
    }

    /// そのタイルが、範囲とズームの幅に含まれるか。消すときに、他の範囲と重なるかを見るのに使います。
    static func covers(_ box: GeoBox, zooms: ClosedRange<Int>, key: TileKey) -> Bool {
        guard zooms.contains(key.z) else { return false }
        let (xs, ys) = range(of: box, z: key.z)
        return xs.contains(key.x) && ys.contains(key.y)
    }
}
