import Foundation

/// 買い出しリストの1行。複数のレシピで同じ材料を使う場合は合算されます。
struct ShoppingItem: Identifiable, Hashable {
    /// 材料の識別子。チェック状態はこれで覚えるので、レシピを選び直しても消えません。
    let id: String
    let name: String
    let aisle: String
    /// 合算した数量。「少々」の材料は nil。
    let quantity: Double?
    let unit: String?
    /// この材料を使うレシピの名前。
    let usedIn: [String]

    var quantityText: String {
        guard let quantity, let unit else { return "少々" }
        return "\(RecipeIngredient.format(quantity))\(unit)"
    }
}

/// 売り場ごとにまとめた買い出しリスト。
struct ShoppingSection: Identifiable {
    var id: String { aisle }
    let aisle: String
    let items: [ShoppingItem]
}

enum ShoppingListBuilder {

    /// 選んだレシピから買い出しリストを組み立てる。
    ///
    /// - Parameter servings: 何人ぶん作るか。レシピごとの既定人数に対する倍率を掛けます。
    ///   2人前のレシピを4人ぶん作るなら、材料は2倍になります。
    static func build(from recipes: [Recipe], servings: Int) -> [ShoppingSection] {
        var totals: [String: ShoppingItem] = [:]
        var order: [String] = []

        for recipe in recipes {
            // レシピごとに既定の人数が違うので、そこを揃えてから掛ける。
            let multiplier = Double(servings) / Double(max(1, recipe.servings))

            for ingredient in recipe.ingredients {
                let scaled = ingredient.quantity.map { $0 * multiplier }

                if let existing = totals[ingredient.id] {
                    totals[ingredient.id] = ShoppingItem(
                        id: existing.id,
                        name: existing.name,
                        aisle: existing.aisle,
                        // 片方でも数量を持たない材料は「少々」のままにする。
                        quantity: sum(existing.quantity, scaled),
                        unit: existing.unit,
                        usedIn: existing.usedIn + [recipe.name]
                    )
                } else {
                    order.append(ingredient.id)
                    totals[ingredient.id] = ShoppingItem(
                        id: ingredient.id,
                        name: ingredient.name,
                        aisle: ingredient.aisle,
                        quantity: scaled,
                        unit: ingredient.unit,
                        usedIn: [recipe.name]
                    )
                }
            }
        }

        let items = order.compactMap { totals[$0] }
        // 売り場ごとにまとめる。店内を行ったり来たりしないで済むように。
        let grouped = Dictionary(grouping: items, by: \.aisle)
        return aisleOrder
            .compactMap { aisle in
                guard let items = grouped[aisle], !items.isEmpty else { return nil }
                return ShoppingSection(aisle: aisle, items: items)
            }
    }

    private static func sum(_ lhs: Double?, _ rhs: Double?) -> Double? {
        guard let lhs, let rhs else { return nil }
        return lhs + rhs
    }

    /// 売り場を並べる順。スーパーを回る動線に近い順にしています。
    private static let aisleOrder = [
        "野菜・果物",
        "肉・魚",
        "乳製品・卵",
        "パン・主食",
        "乾物・保存食",
        "調味料"
    ]
}
