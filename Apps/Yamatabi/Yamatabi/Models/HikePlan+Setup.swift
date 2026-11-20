import CoreLocation
import Foundation

/// 計画に登山口・出発地・山を入れるときの手順。
///
/// 1ページずつ進む作成画面と、詳しい計画画面の両方から同じ入れ方をするため、ここにまとめています。
/// 片方だけ直して、標高差やコースタイムの入り方が画面によって違う、ということを防ぐためです。
@MainActor
extension HikePlan {

    /// 登山口を決め、標高を取りに行き、概算のコースタイムを入れる。
    ///
    /// 標高が取れなくても登山口そのものは決まったままにします。電波の弱い場所で
    /// 選び直しを強いるより、あとでコースタイムを手で入れてもらうほうが早いためです。
    func applyTrailhead(name: String, coordinate: CLLocationCoordinate2D) async {
        trailheadName = name
        trailheadLatitude = coordinate.latitude
        trailheadLongitude = coordinate.longitude

        guard let elevation = try? await ElevationService.elevation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        ) else { return }

        trailheadElevation = elevation
        // 手で入れた値や調べた値は尊重し、概算のときだけ入れ替える。
        if courseTimeSource == .estimated || courseTimeSeconds == 0 {
            let gain = max(0, summitElevation - elevation)
            courseTimeSeconds = HikePlanner.estimatedCourseTime(elevationGain: gain)
            courseTimeSource = .estimated
        }
    }

    func setOrigin(name: String, coordinate: CLLocationCoordinate2D) {
        originName = name
        originLatitude = coordinate.latitude
        originLongitude = coordinate.longitude
    }

    /// 出発地から登山口までの車の時間を計算し直す。どちらかが無ければ何もしない。
    func refreshDrive() async throws {
        guard let origin = originCoordinate, let trailhead = trailheadCoordinate else { return }
        let estimate = try await RouteService.drive(from: origin, to: trailhead)
        driveTimeSeconds = estimate.travelTime
        driveDistance = estimate.distance
        estimatedHighwayDistance = estimate.estimatedHighwayDistance
        highwayNamesText = estimate.highwayNames.joined(separator: "・")
    }
}

extension HikePlan {
    /// 計画の山を差し替える。
    ///
    /// 登山口・ルート・コースタイム・車の時間は山ごとに違うので消します。残すと、
    /// 前の山の登山口から新しい山へ登る時間割ができてしまいます。
    /// 日付・出発地・時間割の決め方・山ごはんは、山に依らないので残します。
    func change(to mountain: Mountain) {
        guard mountain.id != mountainID else { return }

        mountainID = mountain.id
        mountainName = mountain.displayName
        summitLatitude = mountain.latitude
        summitLongitude = mountain.longitude
        summitElevation = Double(mountain.elevation)

        trailheadName = nil
        trailheadLatitude = nil
        trailheadLongitude = nil
        trailheadElevation = nil
        parkingNote = nil

        routeName = nil
        routeStartName = nil
        routeFitnessLevel = nil
        routeDifficultyLevel = nil
        routeLengthKm = nil
        routeIsRoundTrip = nil
        courseTimeSeconds = 0
        courseTimeSourceRaw = CourseTimeSource.estimated.rawValue

        driveTimeSeconds = nil
        driveDistance = nil
        estimatedHighwayDistance = nil
        highwayNamesText = nil
        tollAmountOverride = nil
    }
}
