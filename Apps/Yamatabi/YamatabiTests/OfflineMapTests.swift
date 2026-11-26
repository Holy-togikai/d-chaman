import Foundation
import Testing

@testable import Yamatabi

/// オフライン地図の計算と決まりごと。
///
/// 量の上限は、国土地理院のサーバーに過大な負荷をかけないための約束です（決定記録 0001）。
/// 緩めるとアプリの利用者全員の地図が遮断されうるので、テストで守っています。
struct OfflineMapTests {

    /// 雲取山の山頂の周り、およそ10km四方。
    private static let kumotori = GeoBox(
        minLatitude: 35.81, maxLatitude: 35.90,
        minLongitude: 138.89, maxLongitude: 139.00
    )

    // MARK: - タイルの番号

    /// 地理院地図で確かめた値。東京駅はズーム15で (29105, 12903)。
    @Test func 東京駅のタイル番号() {
        #expect(TileMath.x(longitude: 139.7671, z: 15) == 29105)
        #expect(TileMath.y(latitude: 35.6812, z: 15) == 12903)
    }

    @Test func ズーム0は世界で1枚() {
        #expect(TileMath.x(longitude: 139.7, z: 0) == 0)
        #expect(TileMath.y(latitude: 35.6, z: 0) == 0)
    }

    /// 北ほど縦の番号が小さい。範囲の向きを取り違えると、枚数が0になってしまいます。
    @Test func 北のほうが縦の番号が小さい() {
        #expect(TileMath.y(latitude: 36, z: 12) < TileMath.y(latitude: 35, z: 12))
    }

    @Test func 範囲の枚数はズームごとの合計() {
        let perZoom = (10...12).map { TileMath.count(of: Self.kumotori, zooms: $0...$0) }
        #expect(TileMath.count(of: Self.kumotori, zooms: 10...12) == perZoom.reduce(0, +))
        #expect(perZoom.allSatisfy { $0 >= 1 })
    }

    @Test func 並べたタイルの数と見積もりが一致する() {
        let keys = TileMath.keys(of: Self.kumotori, zooms: 10...14, tile: .standard)
        #expect(keys.count == TileMath.count(of: Self.kumotori, zooms: 10...14))
        #expect(Set(keys).count == keys.count, "同じタイルが2回入っています")
    }

    /// ひとつ上のズームのタイルは、番号を半分にしたもの。拡大表示で親を探すのに使います。
    @Test func 親のタイルは番号が半分() throws {
        let key = TileKey(tile: .standard, z: 16, x: 58211, y: 25807)
        let parent = try #require(key.ancestor(levelsUp: 1))
        #expect(parent == TileKey(tile: .standard, z: 15, x: 29105, y: 12903))
        let grand = try #require(key.ancestor(levelsUp: 2))
        #expect(grand.z == 14 && grand.x == 14552 && grand.y == 6451)
        #expect(TileKey(tile: .standard, z: 0, x: 0, y: 0).ancestor(levelsUp: 1) == nil)
    }

    // MARK: - 量の上限

    /// 山1つ（10km四方ほど）は、上限の中に収まること。収まらないと実用になりません。
    @Test func 山ひとつ分は上限に収まる() {
        let count = TileMath.count(of: Self.kumotori, zooms: OfflineMapPolicy.zooms)
        #expect(count <= OfflineMapPolicy.maximumTilesPerArea, "雲取山の周りで \(count) 枚")
        #expect(count >= 100, "少なすぎます。計算を疑ってください: \(count) 枚")
    }

    /// 県1つ分のような広い範囲は、上限を超えて止められること。
    @Test func 広すぎる範囲は上限を超える() {
        let yamanashi = GeoBox(minLatitude: 35.2, maxLatitude: 35.95, minLongitude: 138.2, maxLongitude: 139.1)
        let count = TileMath.count(of: yamanashi, zooms: OfflineMapPolicy.zooms)
        #expect(count > OfflineMapPolicy.maximumTilesPerArea)
    }

    /// 負荷の上限を緩めすぎていないこと。ここを変えるなら、決定記録 0001 を読み直してください。
    @Test func 取りに行く速さが抑えられている() {
        #expect(OfflineMapPolicy.concurrentRequests <= 4)
        #expect(OfflineMapPolicy.intervalBetweenRequests >= 0.05)
        #expect(OfflineMapPolicy.zooms.upperBound <= 16, "17以上は枚数が膨らみすぎます")
        #expect(OfflineMapPolicy.maximumTilesPerArea <= 5000)
    }

    // MARK: - 消すとき

    /// 2つの保存範囲が重なっているとき、片方を消しても、もう片方のタイルは残す。
    @Test func 重なっているタイルは消さない() {
        let east = GeoBox(minLatitude: 35.81, maxLatitude: 35.90, minLongitude: 138.95, maxLongitude: 139.05)
        let keys = TileMath.keys(of: Self.kumotori, zooms: 12...14, tile: .standard)
        let removable = OfflineMapPolicy.removableKeys(
            of: keys,
            keeping: [.init(tile: .standard, box: east, zooms: 12...14)]
        )
        #expect(!removable.isEmpty, "重ならない部分は消えるはず")
        #expect(removable.count < keys.count, "重なる部分は残るはず")
        let kept = removable.filter { TileMath.covers(east, zooms: 12...14, key: $0) }
        #expect(kept.isEmpty, "残すべきタイルを消そうとしています")
    }

    /// 地図の種類が違えば、同じ範囲でも別のタイル。消してよい。
    @Test func 種類が違えば重なりとみなさない() {
        let keys = TileMath.keys(of: Self.kumotori, zooms: 12...13, tile: .standard)
        let removable = OfflineMapPolicy.removableKeys(
            of: keys,
            keeping: [.init(tile: .photo, box: Self.kumotori, zooms: 12...13)]
        )
        #expect(removable.count == keys.count)
    }

    // MARK: - 出所の表示

    /// 写真は、地理院タイル一覧の備考で Landsat8 の出所表示が求められている。
    @Test func 写真には追加の出所を出す() {
        let text = GSITile.photo.extraAttribution ?? ""
        #expect(text.contains("Landsat8"))
        #expect(text.contains("GEBCO"))
        #expect(GSITile.standard.extraAttribution == nil)
    }

    /// 写真の粗いズームは、別の長い出所表示が要る画像なので、標準地図に差し替える。
    @Test func 写真の粗いズームは標準地図に差し替える() {
        let low = GSITile.photo.url(z: GSITile.photoMinimumZ - 1, x: 0, y: 0)?.absoluteString ?? ""
        #expect(low.contains("/std/"))
        let high = GSITile.photo.url(z: GSITile.photoMinimumZ, x: 0, y: 0)?.absoluteString ?? ""
        #expect(high.contains("/seamlessphoto/"))
    }

    @Test func 保存は配信元と同じ形式() {
        #expect(GSITile.standard.fileExtension == "png")
        #expect(GSITile.photo.fileExtension == "jpg")
    }
}
