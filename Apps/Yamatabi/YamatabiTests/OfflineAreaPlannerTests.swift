import CoreLocation
import Testing

@testable import Yamatabi

/// オフライン地図の範囲を自動で決める決まり。
///
/// 利用者に範囲を選ばせると、選び間違いで膨大な通信が起きます。範囲はアプリが決めるので、
/// 「登山道が切れない」「通信が膨らまない」の両方をここで守ります。
struct OfflineAreaPlannerTests {

    /// 北岳の山頂と、登山口の広河原。
    private static let kitadake = CLLocationCoordinate2D(latitude: 35.6743, longitude: 138.2388)
    private static let hirogawara = CLLocationCoordinate2D(latitude: 35.7031, longitude: 138.3104)

    @Test func 山頂と登山口の両方が入る() throws {
        let plan = try #require(OfflineAreaPlanner.plan(
            summit: Self.kitadake, trailhead: Self.hirogawara, routeLengthKm: nil
        ))
        #expect(plan.box.contains(Self.kitadake))
        #expect(plan.box.contains(Self.hirogawara))
    }

    /// 駐車場が満車で少し離れた所に停めても、地図が切れないこと。
    @Test func 登山口から2km離れた駐車場まで入る() throws {
        let plan = try #require(OfflineAreaPlanner.plan(
            summit: Self.kitadake, trailhead: Self.hirogawara, routeLengthKm: nil
        ))
        // 緯度1度は約111km。北へ1.8km、東へ1.8km ずらした地点。
        let farParking = CLLocationCoordinate2D(
            latitude: Self.hirogawara.latitude + 1.8 / 111,
            longitude: Self.hirogawara.longitude + 1.8 / (111 * cos(Self.hirogawara.latitude * .pi / 180))
        )
        #expect(plan.box.contains(farParking))
    }

    /// ふつうの山なら、いちばん細かいズーム（16）まで、上限の内側で取れる。
    @Test func ふつうの山はズーム16まで上限内に収まる() throws {
        let plan = try #require(OfflineAreaPlanner.plan(
            summit: Self.kitadake, trailhead: Self.hirogawara, routeLengthKm: nil
        ))
        #expect(plan.zooms.upperBound == 16)
        #expect(plan.tileCount <= OfflineMapPolicy.maximumTilesPerArea)
        #expect(plan.tileCount >= 200, "少なすぎます。計算を疑ってください: \(plan.tileCount)")
    }

    /// 登山口が決まっていなくても、山頂のまわりを取る。
    @Test func 登山口が無くても山頂のまわりを取る() throws {
        let plan = try #require(OfflineAreaPlanner.plan(
            summit: Self.kitadake, trailhead: nil, routeLengthKm: nil
        ))
        #expect(plan.box.contains(Self.kitadake))
        // 既定（往復10km）の半分＝山頂から5km先まで入る。
        let fiveKmNorth = CLLocationCoordinate2D(
            latitude: Self.kitadake.latitude + 4.9 / 111, longitude: Self.kitadake.longitude
        )
        #expect(plan.box.contains(fiveKmNorth))
    }

    /// コースが長くても、半径は上限で止まる。通信量を膨らませないため。
    @Test func コースが長くても半径は上限で止まる() {
        let long = OfflineAreaPlanner.box(summit: Self.kitadake, trailhead: nil, routeLengthKm: 40)
        let capped = OfflineAreaPlanner.expanded(
            around: Self.kitadake, km: OfflineAreaPlanner.radiusWithoutTrailheadKm.upperBound
        )
        #expect(long == capped)
    }

    /// コースが短くても、半径は下限より狭くしない。登山道が切れないように。
    @Test func コースが短くても半径は下限を保つ() {
        let short = OfflineAreaPlanner.box(summit: Self.kitadake, trailhead: nil, routeLengthKm: 1)
        let floor = OfflineAreaPlanner.expanded(
            around: Self.kitadake, km: OfflineAreaPlanner.radiusWithoutTrailheadKm.lowerBound
        )
        #expect(short == floor)
    }

    /// 登山口が遠すぎる（入力の間違いなど）ときは、黙って膨大な量を取りに行かない。
    @Test func 登山口が遠すぎると保存しない() {
        let tokyoStation = CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671)
        let plan = OfflineAreaPlanner.plan(
            summit: Self.kitadake, trailhead: tokyoStation, routeLengthKm: nil
        )
        #expect(plan == nil)
    }

    /// 区切りの内側でいちばん遠い登山口でも、ズーム16まで上限の内側に収まる。
    /// 区切り（20km）と枚数の上限（3,000枚）が食い違っていないことの確かめです。
    @Test func 区切りの内側なら上限に収まる() throws {
        // 北東へ斜めに約19km。範囲がいちばん広くなる向き。
        let offset = 13.4
        let far = CLLocationCoordinate2D(
            latitude: Self.kitadake.latitude + offset / 111,
            longitude: Self.kitadake.longitude + offset / (111 * cos(Self.kitadake.latitude * .pi / 180))
        )
        #expect(OfflineAreaPlanner.distanceKm(Self.kitadake, far) < OfflineAreaPlanner.maximumTrailheadDistanceKm)
        let plan = try #require(OfflineAreaPlanner.plan(summit: Self.kitadake, trailhead: far, routeLengthKm: nil))
        #expect(plan.zooms.upperBound == 16)
        #expect(plan.tileCount <= OfflineMapPolicy.maximumTilesPerArea, "\(plan.tileCount) 枚")
    }

    /// 登山口が区切りより遠ければ、枚数に関わらず保存しない。
    @Test func 区切りより遠い登山口は保存しない() {
        let far = CLLocationCoordinate2D(latitude: Self.kitadake.latitude, longitude: Self.kitadake.longitude + 0.3)
        #expect(OfflineAreaPlanner.distanceKm(Self.kitadake, far) > OfflineAreaPlanner.maximumTrailheadDistanceKm)
        #expect(OfflineAreaPlanner.plan(summit: Self.kitadake, trailhead: far, routeLengthKm: nil) == nil)
    }
}
