import CoreLocation
import Foundation
import SwiftData

/// 登山の計画。
///
/// 逆算した時刻は保存していません。日付や登山口を変えれば結果も変わるため、
/// 表示のたびに `HikePlanner` で計算し直します。保存するのは入力値だけです。
@Model
final class HikePlan {
    var id: UUID = UUID()
    var createdAt: Date = Date()

    /// 登る日。
    var date: Date = Date()

    // --- 山（国土地理院のデータから転記）---
    var mountainID: String = ""
    var mountainName: String = ""
    var summitLatitude: Double = 0
    var summitLongitude: Double = 0
    var summitElevation: Double = 0

    // --- 登山口（駐車場を選ぶか、地図で指定）---
    var trailheadName: String?
    var trailheadLatitude: Double?
    var trailheadLongitude: Double?
    /// 登山口の標高。山頂との差がコースタイムの見積もりに効きます。
    var trailheadElevation: Double?
    /// 駐車場の料金や台数のメモ。公開データが無いため手で記録してもらいます。
    var parkingNote: String?

    // --- 出発地 ---
    var originName: String?
    var originLatitude: Double?
    var originLongitude: Double?

    // --- 行動時間 ---
    /// ガイドブック等の標準コースタイム（往復・秒）。
    var courseTimeSeconds: TimeInterval = 0
    /// コースタイムの根拠。「標高差からの概算」なのか調べた値なのかを区別します。
    var courseTimeSourceRaw: String = CourseTimeSource.estimated.rawValue
    /// ペース倍率。
    var paceRaw: Double = HikePace.standard.rawValue

    // --- 選んだ登山ルート（調査済みデータから）---
    var routeName: String?
    /// ルートの登山口の地名。駐車場を探すときの手がかりになります。
    var routeStartName: String?
    var routeFitnessLevel: Int?
    var routeDifficultyLevel: String?
    var routeLengthKm: Double?
    /// 往復できるルートか。違う場合は車の回収方法を考える必要があります。
    var routeIsRoundTrip: Bool?

    // --- 移動（計算結果のキャッシュ。経路計算は通信を伴うため毎回は行わない）---
    var driveTimeSeconds: TimeInterval?
    var driveDistance: Double?
    var estimatedHighwayDistance: Double?
    var highwayNamesText: String?
    /// 高速料金。概算を手で上書きできます。
    var tollAmountOverride: Int?

    init(mountain: Mountain, date: Date) {
        self.id = UUID()
        self.createdAt = Date()
        self.date = date
        self.mountainID = mountain.id
        self.mountainName = mountain.displayName
        self.summitLatitude = mountain.latitude
        self.summitLongitude = mountain.longitude
        self.summitElevation = Double(mountain.elevation)
        self.courseTimeSeconds = 0
        self.courseTimeSourceRaw = CourseTimeSource.estimated.rawValue
        self.paceRaw = HikePace.standard.rawValue
    }

    // MARK: - 取り回しやすくするための計算プロパティ

    var pace: HikePace {
        get { HikePace(rawValue: paceRaw) ?? .standard }
        set { paceRaw = newValue.rawValue }
    }

    var courseTimeSource: CourseTimeSource {
        get { CourseTimeSource(rawValue: courseTimeSourceRaw) ?? .estimated }
        set { courseTimeSourceRaw = newValue.rawValue }
    }

    var summitCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: summitLatitude, longitude: summitLongitude)
    }

    var trailheadCoordinate: CLLocationCoordinate2D? {
        guard let trailheadLatitude, let trailheadLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: trailheadLatitude, longitude: trailheadLongitude)
    }

    var originCoordinate: CLLocationCoordinate2D? {
        guard let originLatitude, let originLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: originLatitude, longitude: originLongitude)
    }

    /// 山頂と登山口の標高差。登山口が未設定なら nil。
    var elevationGain: Double? {
        guard let trailheadElevation else { return nil }
        return max(0, summitElevation - trailheadElevation)
    }

    /// 高速料金。手入力があればそれを、無ければ距離からの概算を返します。
    var tollEstimate: TollEstimate? {
        if let tollAmountOverride {
            return TollEstimate(manualAmount: tollAmountOverride)
        }
        guard let estimatedHighwayDistance, estimatedHighwayDistance > 0 else { return nil }
        return TollEstimate(highwayDistance: estimatedHighwayDistance)
    }

    /// 逆算した時刻。登山口と移動時間が未設定でも、分かる範囲で計算します。
    func schedule() -> HikeSchedule? {
        HikePlanner.schedule(
            HikePlanner.Input(
                latitude: summitLatitude,
                longitude: summitLongitude,
                elevation: summitElevation,
                date: date,
                courseTime: courseTimeSeconds,
                pace: pace,
                driveTime: driveTimeSeconds ?? 0
            )
        )
    }

    /// 選んだルートの要約。「体力度5 ・ 難易度B ・ 18.1km」
    var routeGradeText: String? {
        guard let routeFitnessLevel, let routeDifficultyLevel, let routeLengthKm else { return nil }
        return String(
            format: "体力度%d ・ 難易度%@ ・ %.1fkm",
            routeFitnessLevel, routeDifficultyLevel, routeLengthKm
        )
    }

    /// 選んだルートを計画に反映する。
    func apply(route: CourseRoute) {
        routeName = route.shortTitle
        routeStartName = route.startName
        routeFitnessLevel = route.fitnessLevel
        routeDifficultyLevel = route.difficultyLevel
        routeLengthKm = route.lengthKm
        routeIsRoundTrip = route.isRoundTrip
        courseTimeSeconds = route.courseTime
        courseTimeSource = .researched
    }

    /// 計画として成立しているか。足りない項目を文章で返します。
    var missingPieces: [String] {
        var missing: [String] = []
        if trailheadCoordinate == nil { missing.append("登山口") }
        if originCoordinate == nil { missing.append("出発地") }
        if courseTimeSeconds <= 0 { missing.append("コースタイム") }
        return missing
    }
}

/// コースタイムの根拠。
enum CourseTimeSource: String, Codable {
    /// 標高差から機械的に見積もった値。
    case estimated
    /// ガイドブックや登山地図で調べた値。
    case researched
    /// 利用者が手で入れた値。
    case manual

    var label: String {
        switch self {
        case .estimated: "標高差からの概算"
        case .researched: "調査した標準コースタイム"
        case .manual: "手入力"
        }
    }

    /// 概算は外れることがあるので、画面で注意を促すかどうか。
    var needsCaution: Bool { self == .estimated }
}
