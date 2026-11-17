import Foundation

/// 調査済みの登山ルート。標準コースタイムと、公式の体力度・難易度が入っています。
///
/// 出典: 各県が公表する「山のグレーディング」一覧表。
/// 詳しくは README の「コースタイムのデータ」を参照。
struct CourseRoute: Identifiable, Codable, Hashable {
    /// 地理院の山ID（副峰の枝番を含む）。
    let mountainID: String
    let mountainName: String
    /// ルート名称。「【周】大朝日岳（朝日鉱泉口）＜中ツル尾根＞」のような形。
    let route: String
    /// 登山口の地名。駐車場を探すときの手がかりになります。
    let startName: String
    let startElevation: Double
    let summitName: String
    let endName: String
    /// 出発地点と終了地点が同じか。違う場合は縦走・周回で、車で戻れない点に注意が要ります。
    let isRoundTrip: Bool
    /// 合計コースタイム（時間）。
    let courseTimeHours: Double
    let lengthKm: Double
    /// 体力度 1〜10。大きいほど体力を要します。
    let fitnessLevel: Int
    /// 技術的難易度 A〜E。A がやさしく、E ほど高度な技術を要します。
    let difficultyLevel: String
    let prefecture: String

    var id: String { "\(mountainID)|\(route)" }

    var courseTime: TimeInterval { courseTimeHours * 3600 }

    /// 「体力度5 ・ 難易度B ・ 18.1km」
    var gradeText: String {
        String(format: "体力度%d ・ 難易度%@ ・ %.1fkm", fitnessLevel, difficultyLevel, lengthKm)
    }

    /// ルート名から飾りを取り除いた、一覧で読みやすい表記。
    var shortTitle: String {
        route
            .replacingOccurrences(of: "【周】", with: "")
            .replacingOccurrences(of: "【縦】", with: "")
    }

    /// 周回・縦走の注意書き。車で来る場合は戻り方を考える必要があります。
    var returnWarning: String? {
        isRoundTrip ? nil : "\(startName) から入り \(endName) に下ります。車の回収方法を確認してください。"
    }
}

/// 同梱している登山ルートのデータ。
///
/// 出典: 各県が公表する「山のグレーディング」一覧表。
/// 詳しくは README の「コースタイムのデータ」を参照。
/// `Tools/parse_grading.py` と `Tools/match_routes.py` で、公表されている PDF から
/// 生成しています。**全国すべての山を網羅してはいません**（百名山を中心に75山）。
/// 収録が無い山では、標高差からの概算を使ってください。
enum CourseRouteData {

    static let all: [CourseRoute] = load()

    /// 指定した山のルート。コースタイムが短い順に返します。
    ///
    /// 地理院のIDは「204-1」のように副峰へ枝番が付くため、枝番を外した単位で照合します。
    /// 蔵王山の熊野岳と刈田岳のどちらを選んでいても、同じ山のルートが出るようにするためです。
    static func routes(for mountainID: String) -> [CourseRoute] {
        let group = indexGroup(mountainID)
        return all
            .filter { indexGroup($0.mountainID) == group }
            .sorted { $0.courseTimeHours < $1.courseTimeHours }
    }

    private static func indexGroup(_ identifier: String) -> String {
        identifier.split(separator: "-").first.map(String.init) ?? identifier
    }

    private static func load() -> [CourseRoute] {
        guard let url = Bundle.main.url(forResource: "courseRoutes", withExtension: "json") else {
            assertionFailure("courseRoutes.json がアプリに同梱されていません")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([CourseRoute].self, from: data)
        } catch {
            assertionFailure("courseRoutes.json を読み込めませんでした: \(error)")
            return []
        }
    }
}
