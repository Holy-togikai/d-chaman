import CoreLocation
import Foundation

/// 車種。高速料金の概算に使います。
///
/// 倍率は NEXCO の車種区分における普通車を 1.0 とした、一般的な比率です。
/// あくまで概算で、割引や区間ごとの差は反映されません。
enum VehicleClass: String, CaseIterable, Identifiable, Codable {
    case kei
    case standard
    case medium

    var id: String { rawValue }

    var label: String {
        switch self {
        case .kei: "軽自動車"
        case .standard: "普通車"
        case .medium: "中型車"
        }
    }

    /// 普通車を 1.0 としたときの料金の倍率。
    var tollMultiplier: Double {
        switch self {
        case .kei: 0.8
        case .standard: 1.0
        case .medium: 1.2
        }
    }
}

/// アプリ全体で使う設定。計画をまたいで使い回す値を持ちます。
///
/// 登山記録や計画と違って量が少なく、1件しか無いものなので、
/// データベースではなく `UserDefaults` に置いています。
@MainActor
final class UserSettings: ObservableObject {

    static let shared = UserSettings()

    private enum Key {
        static let homeName = "home.name"
        static let homeLatitude = "home.latitude"
        static let homeLongitude = "home.longitude"
        static let vehicleClass = "vehicle.class"
    }

    private let defaults = UserDefaults.standard

    @Published var homeName: String? {
        didSet { defaults.set(homeName, forKey: Key.homeName) }
    }

    @Published var vehicleClass: VehicleClass {
        didSet { defaults.set(vehicleClass.rawValue, forKey: Key.vehicleClass) }
    }

    private(set) var homeLatitude: Double?
    private(set) var homeLongitude: Double?

    private init() {
        homeName = defaults.string(forKey: Key.homeName)
        homeLatitude = defaults.object(forKey: Key.homeLatitude) as? Double
        homeLongitude = defaults.object(forKey: Key.homeLongitude) as? Double
        vehicleClass = VehicleClass(
            rawValue: defaults.string(forKey: Key.vehicleClass) ?? ""
        ) ?? .standard
    }

    var homeCoordinate: CLLocationCoordinate2D? {
        guard let homeLatitude, let homeLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: homeLatitude, longitude: homeLongitude)
    }

    var hasHome: Bool { homeCoordinate != nil }

    func setHome(name: String, coordinate: CLLocationCoordinate2D) {
        homeName = name
        homeLatitude = coordinate.latitude
        homeLongitude = coordinate.longitude
        defaults.set(coordinate.latitude, forKey: Key.homeLatitude)
        defaults.set(coordinate.longitude, forKey: Key.homeLongitude)
        objectWillChange.send()
    }

    func clearHome() {
        homeName = nil
        homeLatitude = nil
        homeLongitude = nil
        defaults.removeObject(forKey: Key.homeLatitude)
        defaults.removeObject(forKey: Key.homeLongitude)
        objectWillChange.send()
    }
}
