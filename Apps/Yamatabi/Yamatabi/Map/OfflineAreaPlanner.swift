import CoreLocation
import Foundation

/// オフライン地図として保存する範囲を、山と登山口から自動で決める。
///
/// 範囲を利用者に選ばせていたところ、地図を広く表示したまま保存して膨大な通信が
/// 起きる恐れがある、という指摘を受けました（日本全体を選ぶと2,500万枚になる）。
/// 範囲はアプリが決め、利用者は「保存する」を押すだけにしています。
enum OfflineAreaPlanner {

    /// 登山口のまわりに足す余白（km）。
    ///
    /// 登山口の駐車場が満車で、少し離れた駐車場から歩くことはよくあります。
    /// 2km あれば、たいていの第2・第3駐車場まで入ります。
    static let trailheadMarginKm = 2.0

    /// 山頂のまわりに必ず取る余白（km）。山頂の向こう側へ下りる道や、周りの峰を含めるため。
    static let summitMarginKm = 2.0

    /// 登山口が決まっていないときに、山頂から取る半径（km）の下限と上限。
    ///
    /// コースの長さ（往復）の半分を目安にしますが、短すぎると登山道が切れ、
    /// 長すぎると通信量が膨らむので、この幅に収めます。
    static let radiusWithoutTrailheadKm = 3.0...8.0

    /// 登山口もコースも分からないときに仮に置く、コースの長さ（往復、km）。
    static let defaultRouteLengthKm = 10.0

    struct Plan: Equatable {
        let box: GeoBox
        let zooms: ClosedRange<Int>
        let tileCount: Int
    }

    /// 山頂と登山口がこれ以上離れていたら、保存しない（km、直線）。
    ///
    /// 枚数の上限だけでは足りません。東西にだけ長い細い範囲は、遠くても枚数が少なく出るためです
    /// （山頂の真東 140km の東京駅を登山口にしても、上限の内側に収まってしまった）。
    /// 長いアプローチで知られる上高地から槍ヶ岳でも直線で約13kmなので、20km を区切りにします。
    static let maximumTrailheadDistanceKm = 20.0

    /// 保存する範囲とズーム。保存できないときは nil を返します。
    ///
    /// 登山口が遠すぎる（入力の間違いを含む）ときや、枚数が上限を超えるときに、
    /// 黙って膨大な量を取りに行かないためです。
    static func plan(
        summit: CLLocationCoordinate2D,
        trailhead: CLLocationCoordinate2D?,
        routeLengthKm: Double?
    ) -> Plan? {
        if let trailhead, distanceKm(summit, trailhead) > maximumTrailheadDistanceKm {
            return nil
        }
        let box = box(summit: summit, trailhead: trailhead, routeLengthKm: routeLengthKm)
        let zooms = OfflineMapPolicy.zooms
        let count = TileMath.count(of: box, zooms: zooms)
        guard count <= OfflineMapPolicy.maximumTilesPerArea else { return nil }
        return Plan(box: box, zooms: zooms, tileCount: count)
    }

    static func distanceKm(_ from: CLLocationCoordinate2D, _ to: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude)) / 1000
    }

    /// 山頂と登山口を含み、余白を足した範囲。
    static func box(
        summit: CLLocationCoordinate2D,
        trailhead: CLLocationCoordinate2D?,
        routeLengthKm: Double?
    ) -> GeoBox {
        if let trailhead {
            let around = [
                expanded(around: summit, km: summitMarginKm),
                expanded(around: trailhead, km: trailheadMarginKm)
            ]
            return GeoBox(
                minLatitude: around.map(\.minLatitude).min()!,
                maxLatitude: around.map(\.maxLatitude).max()!,
                minLongitude: around.map(\.minLongitude).min()!,
                maxLongitude: around.map(\.maxLongitude).max()!
            )
        }
        // 登山口が分からないときは、コースの長さ（往復）の半分を山頂からの半径にする。
        let half = (routeLengthKm ?? defaultRouteLengthKm) / 2
        let radius = min(max(half, radiusWithoutTrailheadKm.lowerBound), radiusWithoutTrailheadKm.upperBound)
        return expanded(around: summit, km: radius)
    }

    /// 地点のまわりに、東西南北それぞれ km だけ広げた範囲。
    static func expanded(around point: CLLocationCoordinate2D, km: Double) -> GeoBox {
        // 緯度1度はおよそ111km。経度1度は緯度が高いほど短くなる。
        let latitudeDelta = km / 111.0
        let longitudeDelta = km / (111.0 * cos(point.latitude * .pi / 180))
        return GeoBox(
            minLatitude: point.latitude - latitudeDelta,
            maxLatitude: point.latitude + latitudeDelta,
            minLongitude: point.longitude - longitudeDelta,
            maxLongitude: point.longitude + longitudeDelta
        )
    }
}

extension GeoBox {
    func contains(_ point: CLLocationCoordinate2D) -> Bool {
        (minLatitude...maxLatitude).contains(point.latitude)
            && (minLongitude...maxLongitude).contains(point.longitude)
    }
}
