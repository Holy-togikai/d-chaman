import Foundation
import Testing

@testable import Yamatabi

/// 軌跡からの数値の算出。
///
/// 累積標高のヒステリシスがこのテストの中心です。GPS の標高は静止していても
/// 数メートル上下するため、素直に足すと実際の数倍になります。
struct TrackMathTests {

    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    private static func point(
        latitude: Double = 35.3606,
        longitude: Double = 138.7274,
        altitude: Double?,
        after seconds: TimeInterval
    ) -> TrackPoint {
        TrackPoint(
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            timestamp: start.addingTimeInterval(seconds),
            horizontalAccuracy: 5,
            speed: nil
        )
    }

    // MARK: - 累積標高

    /// 3m以下の揺れは無視する。
    ///
    /// 静止したまま標高だけが 1,000 → 1,002 → 1,000 → 1,001 と揺れる状況。
    /// これを足し込むと「のぼり3m」などと出てしまいます。
    @Test func 小さな標高の揺れは累積に足さない() {
        let points = [
            Self.point(altitude: 1000, after: 0),
            Self.point(altitude: 1002, after: 10),
            Self.point(altitude: 1000, after: 20),
            Self.point(altitude: 1001, after: 30),
            Self.point(altitude: 999, after: 40)
        ]
        let stats = TrackMath.statistics(for: points)

        #expect(stats.elevationGain == 0, "3m以下の揺れは無視するはず。実際は \(stats.elevationGain)")
        #expect(stats.elevationLoss == 0, "下りも同様。実際は \(stats.elevationLoss)")
    }

    /// しきい値を超えて上がったぶんは、ちゃんと足す。
    @Test func しきい値を超えた上昇は累積に足す() {
        let points = [
            Self.point(altitude: 1000, after: 0),
            Self.point(altitude: 1010, after: 60),
            Self.point(altitude: 1020, after: 120)
        ]
        let stats = TrackMath.statistics(for: points)

        #expect(stats.elevationGain == 20, "10m＋10m＝20m のはず。実際は \(stats.elevationGain)")
        #expect(stats.elevationLoss == 0)
    }

    @Test func 上りと下りを別々に数える() {
        let points = [
            Self.point(altitude: 1000, after: 0),
            Self.point(altitude: 1100, after: 60),
            Self.point(altitude: 1050, after: 120)
        ]
        let stats = TrackMath.statistics(for: points)

        #expect(stats.elevationGain == 100)
        #expect(stats.elevationLoss == 50)
    }

    /// 揺れながら少しずつ登る、実際の山行に近い形。
    ///
    /// 基準点を動かさずに揺れを無視するので、揺れのぶんが積み上がりません。
    @Test func 揺れながら登っても累積が膨らまない() {
        var points = [Self.point(altitude: 1000, after: 0)]
        var altitude = 1000.0
        // 10回、2m揺らしながら10mずつ登る
        for step in 1...10 {
            altitude += 10
            points.append(Self.point(altitude: altitude + 2, after: Double(step) * 60))
            points.append(Self.point(altitude: altitude, after: Double(step) * 60 + 30))
        }
        let stats = TrackMath.statistics(for: points)

        // 実際の上昇は100m。揺れを足し込んでいれば120m以上になる。
        #expect(
            stats.elevationGain >= 95 && stats.elevationGain <= 115,
            "実際の上昇100m前後に収まるはず。実際は \(stats.elevationGain)"
        )
    }

    /// 標高が取れない点が混ざっても落ちない。
    @Test func 標高が取れない点が混ざっても計算できる() {
        let points = [
            Self.point(altitude: nil, after: 0),
            Self.point(altitude: 1000, after: 60),
            Self.point(altitude: nil, after: 120),
            Self.point(altitude: 1020, after: 180)
        ]
        let stats = TrackMath.statistics(for: points)

        #expect(stats.elevationGain == 20)
        #expect(stats.currentAltitude == 1020, "最後に標高が取れた点の値を使うはず")
    }

    @Test func 標高が一度も取れなければ現在標高はnil() {
        let points = [
            Self.point(altitude: nil, after: 0),
            Self.point(altitude: nil, after: 60)
        ]
        #expect(TrackMath.statistics(for: points).currentAltitude == nil)
    }

    // MARK: - 距離と時間

    @Test func 点が1つ以下なら距離はゼロ() {
        #expect(TrackMath.statistics(for: []).distance == 0)
        #expect(TrackMath.statistics(for: [Self.point(altitude: 1000, after: 0)]).distance == 0)
    }

    /// 緯度0.001度は約111m。おおよその距離が出ていることを見ます。
    @Test func 距離が実際の地球上の距離として計算される() {
        let points = [
            Self.point(latitude: 35.0000, longitude: 138.0, altitude: nil, after: 0),
            Self.point(latitude: 35.0010, longitude: 138.0, altitude: nil, after: 60)
        ]
        let distance = TrackMath.statistics(for: points).distance

        #expect(
            distance > 105 && distance < 120,
            "緯度0.001度は約111mのはず。実際は \(Int(distance))m"
        )
    }

    @Test func 経過時間は最初と最後の差() {
        let points = [
            Self.point(altitude: nil, after: 0),
            Self.point(altitude: nil, after: 1800),
            Self.point(altitude: nil, after: 3600)
        ]
        #expect(TrackMath.statistics(for: points).elapsed == 3600)
    }

    /// 休憩中（ほぼ動いていない）は移動時間に数えない。
    @Test func 止まっている間は移動時間に数えない() {
        // 同じ場所に留まり続ける点列
        let points = (0...10).map { Self.point(altitude: nil, after: Double($0) * 60) }
        let stats = TrackMath.statistics(for: points)

        #expect(stats.elapsed == 600, "経過時間は10分")
        #expect(stats.moving == 0, "動いていないので移動時間は0のはず。実際は \(stats.moving)")
    }

    /// 記録が長く途切れた区間は、移動時間に足さない。
    /// アプリが落ちていた間を「歩いていた」と数えないためです。
    @Test func 長く途切れた区間は移動時間に足さない() {
        let points = [
            Self.point(latitude: 35.0000, longitude: 138.0, altitude: nil, after: 0),
            // 1時間後に、離れた場所で再開
            Self.point(latitude: 35.0100, longitude: 138.0, altitude: nil, after: 3600)
        ]
        let stats = TrackMath.statistics(for: points)

        #expect(stats.elapsed == 3600)
        #expect(stats.moving == 0, "60秒を超える間隔は移動時間に数えないはず")
        #expect(stats.distance > 1000, "距離は足される（実際に移動しているため）")
    }

    // MARK: - 表示の整形

    @Test func 距離の表示は1km以上でkmに切り替わる() {
        var stats = TrackStatistics.zero
        stats.distance = 850
        #expect(stats.distanceText == "850 m")
        stats.distance = 1234
        #expect(stats.distanceText == "1.23 km")
    }

    @Test(arguments: [
        (1800.0, "30分"), (3600.0, "1時間0分"), (4500.0, "1時間15分"), (43200.0, "12時間0分")
    ])
    func 時間の表示(interval: TimeInterval, expected: String) {
        #expect(TrackStatistics.hourMinuteText(interval) == expected)
    }

    /// 0や負の値は時間として出さない。記録していないものを「0分」と書くと、
    /// 記録できているように見えてしまうためです。
    @Test func 時間がゼロや負なら横棒を出す() {
        #expect(TrackStatistics.hourMinuteText(0) == "—")
        #expect(TrackStatistics.hourMinuteText(-100) == "—")
    }
}
