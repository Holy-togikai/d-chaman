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

    // --- 時間割 ---
    /// 何を基準に時間を決めるか。
    var scheduleBasisRaw: String = ScheduleBasis.sunset.rawValue
    /// 自由設定のときに歩き出す時刻（その日の0時からの分）。既定は6:00。
    var startHikingMinutes: Int = 6 * 60
    /// 日の出の何秒後に歩き出すか（日の出基準）。
    var sunriseOffset: TimeInterval = HikePlanner.defaultSunriseOffset
    /// 日の入りの何秒前に下山を終えるか（日没基準）。
    var sunsetMargin: TimeInterval = HikePlanner.defaultSunsetMargin
    /// 休憩の合計。
    var restTime: TimeInterval = HikePlanner.defaultRestTime

    // --- 山ごはん ---
    /// 選んだレシピのID。カンマ区切りで持ちます。
    /// 配列をそのまま持つより、保存の形が単純で移行に強いためです。
    var recipeIDsText: String?
    /// 何人ぶん作るか。
    var mealServings: Int = 2
    /// 買い物を済ませた材料のID。材料で覚えるので、レシピを選び直しても消えません。
    var purchasedIngredientIDsText: String?

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

    /// 高速料金。手入力があればそれを、無ければ距離と車種からの概算を返します。
    func tollEstimate(for vehicle: VehicleClass) -> TollEstimate? {
        if let tollAmountOverride {
            return TollEstimate(manualAmount: tollAmountOverride)
        }
        guard let estimatedHighwayDistance, estimatedHighwayDistance > 0 else { return nil }
        return TollEstimate(highwayDistance: estimatedHighwayDistance, vehicle: vehicle)
    }

    var scheduleBasis: ScheduleBasis {
        get { ScheduleBasis(rawValue: scheduleBasisRaw) ?? .sunset }
        set { scheduleBasisRaw = newValue.rawValue }
    }

    /// 組み立てた時間割。出発地が未設定でも、分かる範囲で計算します。
    func schedule() -> HikeSchedule? {
        HikePlanner.schedule(
            HikePlanner.Input(
                latitude: summitLatitude,
                longitude: summitLongitude,
                elevation: summitElevation,
                date: date,
                courseTime: courseTimeSeconds,
                pace: pace,
                // 移動時間が分からないまま家を出る時刻を出すと、間に合わない計画を
                // 信じてしまう。危険な側に外すので、揃うまでは出さない。
                driveTime: driveTimeSeconds,
                basis: scheduleBasis,
                startHikingMinutes: startHikingMinutes,
                sunriseOffset: sunriseOffset,
                sunsetMargin: sunsetMargin,
                restTime: restTime
            )
        )
    }

    /// 選んだレシピ。
    var recipes: [Recipe] {
        get {
            (recipeIDsText ?? "")
                .split(separator: ",")
                .compactMap { RecipeData.recipe(id: String($0)) }
        }
        set { recipeIDsText = newValue.map(\.id).joined(separator: ",") }
    }

    /// 選んだレシピの調理時間の合計。
    ///
    /// 山で使えるバーナーはふつう1台なので、2品作るなら順番に作ることになります。
    /// そのため単純に足しています。2品で45〜50分、休憩の既定（1時間）の大半を使います。
    ///
    /// **食べる時刻は持ちません。** 山頂で食べるか途中で食べるかは、その日の天気と
    /// 体調で変わります。当たらない時刻を出すより、かかる時間を示すほうが役に立ちます。
    var cookingTime: TimeInterval {
        recipes.reduce(0) { $0 + Double($1.cookingMinutes) * 60 }
    }

    /// 買い物を済ませた材料。
    var purchasedIngredientIDs: Set<String> {
        get { Set((purchasedIngredientIDsText ?? "").split(separator: ",").map(String.init)) }
        set { purchasedIngredientIDsText = newValue.sorted().joined(separator: ",") }
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

    /// 「つぎの山行」を選ぶときの基準になる時刻。
    ///
    /// 登る日ではなく家を出る時刻で見ます。富士宮口のように前日の深夜に出る計画があり、
    /// 日付で選ぶと、すでに車で走っている計画を「明日のこと」として扱ってしまうためです。
    var departureReference: Date {
        schedule().map { $0.leaveHomeAt ?? $0.startHikingAt } ?? date
    }

    /// この計画を「つぎの山行」として出しておく期限。
    ///
    /// 下山したらすぐ消えてしまうと、帰り道で寄り道を探せません。
    /// 下山期限から6時間（帰路のぶん）は残します。
    var relevanceDeadline: Date {
        if let schedule = schedule() {
            return schedule.descentAt.addingTimeInterval(6 * 60 * 60)
        }
        return Calendar.current.startOfDay(for: date).addingTimeInterval(48 * 60 * 60)
    }

    /// まだ先か、いま進行中の計画のうち、いちばん近いもの。
    static func next(from plans: [HikePlan], now: Date = Date()) -> HikePlan? {
        plans
            .filter { now < $0.relevanceDeadline }
            .min { $0.departureReference < $1.departureReference }
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
