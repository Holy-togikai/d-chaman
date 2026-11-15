import CoreLocation

/// 軌跡を構成する1点。
///
/// 登山1回で数千点になるため、SwiftData のレコードとして1点ずつ持たせると重くなります。
/// `HikeRecord` の中に JSON でまとめて格納する前提の、軽量な値型にしてあります。
struct TrackPoint: Codable, Hashable {
    let latitude: Double
    let longitude: Double
    /// 標高（メートル）。取得できなかった場合は `nil`。
    let altitude: Double?
    let timestamp: Date
    /// 水平精度（メートル）。値が小さいほど正確。
    let horizontalAccuracy: Double
    /// 速度（m/s）。取得できなかった場合は `nil`。
    let speed: Double?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

extension TrackPoint {
    /// CoreLocation の測位結果から作る。
    init(_ location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        // 垂直精度が負の値のときは標高が取得できていない。
        self.altitude = location.verticalAccuracy > 0 ? location.altitude : nil
        self.timestamp = location.timestamp
        self.horizontalAccuracy = location.horizontalAccuracy
        self.speed = location.speed >= 0 ? location.speed : nil
    }
}
