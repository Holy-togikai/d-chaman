import Foundation

/// 山で使う調理器具。
enum CookingGear: String, CaseIterable, Identifiable, Codable {
    case stove = "バーナー"
    case pot = "クッカー"
    case mestin = "メスティン"
    case skillet = "フライパン"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .stove: "flame"
        case .pot: "cup.and.saucer"
        case .mestin: "rectangle.portrait"
        case .skillet: "frying.pan"
        }
    }
}

/// レシピの材料1つぶん。
struct RecipeIngredient: Identifiable, Codable, Hashable {
    /// 材料の識別子。同じ材料は同じ id を持ち、買い出しリストで合算できます。
    let id: String
    let name: String
    /// 売り場の分類。買い出しリストをまとめるのに使います。
    let aisle: String
    /// 数量。「塩少々」のように量を決めないものは nil。
    let quantity: Double?
    /// 単位。数量を持たない材料は nil。
    let unit: String?

    /// 「玉ねぎ 1個」「塩 少々」
    func text(multiplier: Double = 1) -> String {
        guard let quantity, let unit else { return "\(name) 少々" }
        return "\(name) \(Self.format(quantity * multiplier))\(unit)"
    }

    /// 1.0 → 「1」、0.5 → 「0.5」。小数点以下の余計な0を出さない。
    static func format(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}

/// 山ごはんのレシピ。
///
/// レシピサイトからの引き写しではなく、山で作ることを前提に書き下ろしたものです。
/// 元データと検証は `Tools/recipes.py` にあります。
struct Recipe: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let summary: String
    /// 必要な調理器具。
    let gear: [CookingGear]
    /// 山での調理時間（分）。
    let cookingMinutes: Int
    /// 手間の目安 1〜5。大きいほど手順が多い。
    let effort: Int
    /// 保冷が要るか。生鮮を使うレシピは夏場に注意が要ります。
    let needsCooler: Bool
    /// 何人ぶんの分量か。
    let servings: Int
    let ingredients: [RecipeIngredient]
    let steps: [String]
    let tips: String

    var gearText: String {
        gear.map(\.rawValue).joined(separator: "・")
    }

    var effortText: String {
        String(repeating: "●", count: effort) + String(repeating: "○", count: 5 - effort)
    }
}

/// 同梱しているレシピ。
enum RecipeData {

    static let all: [Recipe] = load()

    private static func load() -> [Recipe] {
        guard let url = Bundle.main.url(forResource: "recipes", withExtension: "json") else {
            assertionFailure("recipes.json がアプリに同梱されていません")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([Recipe].self, from: data)
        } catch {
            assertionFailure("recipes.json を読み込めませんでした: \(error)")
            return []
        }
    }

    static func recipe(id: String) -> Recipe? {
        all.first { $0.id == id }
    }
}
