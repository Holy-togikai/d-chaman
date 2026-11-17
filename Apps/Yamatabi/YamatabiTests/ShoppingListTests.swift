import Foundation
import Testing

@testable import Yamatabi

/// 買い出しリストの組み立て。
///
/// 人数で換算し、同じ材料を合算し、売り場ごとにまとめる。ここを間違えると
/// 店で足りないものが出ます。山の上では買い足せません。
struct ShoppingListTests {

    /// テスト用の材料。
    private static func ingredient(
        _ id: String,
        _ name: String,
        aisle: String,
        quantity: Double?,
        unit: String?
    ) -> RecipeIngredient {
        RecipeIngredient(id: id, name: name, aisle: aisle, quantity: quantity, unit: unit)
    }

    /// テスト用のレシピ。同梱の recipes.json に依存させないため、ここで組み立てます。
    /// 本物のデータが変わってもテストが壊れないようにするためです。
    private static func recipe(
        id: String,
        name: String,
        servings: Int,
        ingredients: [RecipeIngredient]
    ) -> Recipe {
        Recipe(
            id: id,
            name: name,
            summary: "テスト用",
            gear: [.stove, .pot],
            cookingMinutes: 20,
            effort: 2,
            needsCooler: false,
            servings: servings,
            ingredients: ingredients,
            steps: ["煮る"],
            tips: "テスト用"
        )
    }

    private static var 煮込み: Recipe {
        recipe(id: "stew", name: "トマト煮込み", servings: 2, ingredients: [
            ingredient("onion", "玉ねぎ", aisle: "野菜・果物", quantity: 1, unit: "個"),
            ingredient("bacon", "ベーコン", aisle: "肉・魚", quantity: 100, unit: "g"),
            ingredient("salt", "塩", aisle: "調味料", quantity: nil, unit: nil)
        ])
    }

    private static var スープ: Recipe {
        recipe(id: "soup", name: "白いんげんのスープ", servings: 2, ingredients: [
            ingredient("onion", "玉ねぎ", aisle: "野菜・果物", quantity: 1, unit: "個"),
            ingredient("bacon", "ベーコン", aisle: "肉・魚", quantity: 100, unit: "g"),
            ingredient("salt", "塩", aisle: "調味料", quantity: nil, unit: nil),
            ingredient("bread", "バゲット", aisle: "パン・主食", quantity: 20, unit: "cm")
        ])
    }

    private static func item(_ sections: [ShoppingSection], id: String) -> ShoppingItem? {
        sections.flatMap(\.items).first { $0.id == id }
    }

    // MARK: - 合算

    @Test func 同じ材料を使う2品を選ぶと合算される() throws {
        let sections = ShoppingListBuilder.build(from: [Self.煮込み, Self.スープ], servings: 2)
        let onion = try #require(Self.item(sections, id: "onion"))

        #expect(onion.quantity == 2, "1個＋1個＝2個になるはず。実際は \(onion.quantity ?? -1)")
        #expect(onion.usedIn.count == 2, "2つのレシピで使うことが分かるはず")
        #expect(onion.quantityText == "2個")
    }

    @Test func 片方のレシピにしかない材料はそのまま出る() throws {
        let sections = ShoppingListBuilder.build(from: [Self.煮込み, Self.スープ], servings: 2)
        let bread = try #require(Self.item(sections, id: "bread"))

        #expect(bread.quantity == 20)
        #expect(bread.usedIn == ["白いんげんのスープ"])
    }

    /// 量を決めない材料は、足し算せず「少々」のままにする。
    /// 「少々＋少々＝2少々」のような表示にならないことの確認です。
    @Test func 量を決めない材料は合算されず少々のまま() throws {
        let sections = ShoppingListBuilder.build(from: [Self.煮込み, Self.スープ], servings: 2)
        let salt = try #require(Self.item(sections, id: "salt"))

        #expect(salt.quantity == nil)
        #expect(salt.quantityText == "少々")
    }

    // MARK: - 人数の換算

    @Test func 人数を倍にすると量も倍になる() throws {
        let twoPeople = ShoppingListBuilder.build(from: [Self.煮込み], servings: 2)
        let fourPeople = ShoppingListBuilder.build(from: [Self.煮込み], servings: 4)

        let onion2 = try #require(Self.item(twoPeople, id: "onion"))
        let onion4 = try #require(Self.item(fourPeople, id: "onion"))
        let bacon4 = try #require(Self.item(fourPeople, id: "bacon"))

        #expect(onion2.quantity == 1)
        #expect(onion4.quantity == 2, "2人前のレシピを4人ぶんなら2倍")
        #expect(bacon4.quantity == 200)
    }

    /// レシピごとに既定の人数が違っても、同じ人数ぶんに揃えてから合算する。
    @Test func 既定人数が違うレシピ同士でも正しく合算される() throws {
        let 一人前 = Self.recipe(id: "single", name: "一人前のレシピ", servings: 1, ingredients: [
            Self.ingredient("onion", "玉ねぎ", aisle: "野菜・果物", quantity: 1, unit: "個")
        ])
        // 2人前レシピ（玉ねぎ1個）＋ 1人前レシピ（玉ねぎ1個）を、4人ぶん作る
        // → 2個 ＋ 4個 ＝ 6個
        let sections = ShoppingListBuilder.build(from: [Self.煮込み, 一人前], servings: 4)
        let onion = try #require(Self.item(sections, id: "onion"))

        #expect(onion.quantity == 6, "2個＋4個＝6個のはず。実際は \(onion.quantity ?? -1)")
    }

    @Test func 人数が1でも計算できる() throws {
        let sections = ShoppingListBuilder.build(from: [Self.煮込み], servings: 1)
        let onion = try #require(Self.item(sections, id: "onion"))
        #expect(onion.quantity == 0.5, "2人前の半分なので0.5個")
        #expect(onion.quantityText == "0.5個")
    }

    // MARK: - 売り場ごとの並び

    /// 店内を行ったり来たりしないよう、売り場の順に並べる。
    @Test func 売り場の順に並ぶ() {
        let sections = ShoppingListBuilder.build(from: [Self.煮込み, Self.スープ], servings: 2)
        let aisles = sections.map(\.aisle)

        #expect(aisles == ["野菜・果物", "肉・魚", "パン・主食", "調味料"], "店を回る順に並ぶはず")
    }

    @Test func レシピを選んでいなければ空になる() {
        #expect(ShoppingListBuilder.build(from: [], servings: 2).isEmpty)
    }

    // MARK: - 表示の整形

    @Test(arguments: [(1.0, "1"), (2.0, "2"), (0.5, "0.5"), (1.5, "1.5"), (10.0, "10")])
    func 数量の表示に余計な小数点が付かない(value: Double, expected: String) {
        #expect(RecipeIngredient.format(value) == expected)
    }

    @Test func 材料の表示文字列() {
        let onion = Self.ingredient("onion", "玉ねぎ", aisle: "野菜・果物", quantity: 1, unit: "個")
        let salt = Self.ingredient("salt", "塩", aisle: "調味料", quantity: nil, unit: nil)

        #expect(onion.text() == "玉ねぎ 1個")
        #expect(onion.text(multiplier: 2) == "玉ねぎ 2個")
        #expect(salt.text() == "塩 少々")
        #expect(salt.text(multiplier: 4) == "塩 少々", "倍率を掛けても少々のまま")
    }
}
