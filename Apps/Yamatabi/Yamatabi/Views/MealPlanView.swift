import SwiftUI

/// 山ごはんを選び、買い出しリストを作る画面。
struct MealPlanView: View {
    @Bindable var plan: HikePlan

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = UserSettings.shared
    @State private var isChoosingRecipes = false

    private var selected: [Recipe] { plan.recipes }

    private var sections: [ShoppingSection] {
        ShoppingListBuilder.build(from: selected, servings: plan.mealServings)
    }

    var body: some View {
        NavigationStack {
            List {
                servingsSection
                recipesSection
                if !selected.isEmpty {
                    shoppingSection
                }
            }
            .navigationTitle("山ごはん")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .sheet(isPresented: $isChoosingRecipes) {
                RecipePickerView(selected: plan.recipes) { recipes in
                    plan.recipes = recipes
                }
            }
            .overlay {
                if selected.isEmpty {
                    EmptyStateView(
                        title: "まだ決めていません",
                        message: "レシピを選ぶと、材料をまとめた買い出しリストを作ります。",
                        systemImage: "fork.knife"
                    )
                }
            }
        }
    }

    private var servingsSection: some View {
        Section {
            Stepper(value: $plan.mealServings, in: 1...8) {
                LabeledContent("作る人数", value: "\(plan.mealServings) 人ぶん")
            }

            Button {
                isChoosingRecipes = true
            } label: {
                Label(
                    selected.isEmpty ? "レシピを選ぶ" : "レシピを選び直す",
                    systemImage: "book"
                )
            }
        } footer: {
            Text("人数を変えると、材料の量も一緒に変わります。")
        }
    }

    @ViewBuilder
    private var recipesSection: some View {
        if !selected.isEmpty {
            Section("選んだレシピ") {
                ForEach(selected) { recipe in
                    NavigationLink {
                        RecipeDetailView(recipe: recipe, servings: plan.mealServings)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recipe.name).font(.body.weight(.medium))
                            Text("\(recipe.cookingMinutes)分 ・ \(recipe.gearText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if recipe.needsCooler {
                                Label("要保冷", systemImage: "snowflake")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var shoppingSection: some View {
        ForEach(sections) { section in
            Section {
                ForEach(section.items) { item in
                    Button {
                        toggle(item)
                    } label: {
                        row(item)
                    }
                    .tint(.primary)
                }
            } header: {
                Text(section.aisle)
            }
        }

        Section {
            if plan.purchasedIngredientIDs.isEmpty {
                Text("買ったものをタップすると、印が付きます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("チェックをすべて外す", role: .destructive) {
                    plan.purchasedIngredientIDs = []
                }
            }
        } footer: {
            if selected.contains(where: \.needsCooler) {
                Label(
                    "保冷が要る材料があります。夏場はクーラーバッグか、凍らせた食材を保冷剤代わりに。",
                    systemImage: "snowflake"
                )
                .font(.caption)
                .foregroundStyle(.blue)
            }
        }
    }

    private func row(_ item: ShoppingItem) -> some View {
        let isDone = plan.purchasedIngredientIDs.contains(item.id)
        return HStack(spacing: 12) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isDone ? Color.brandGreen : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .strikethrough(isDone)
                    .foregroundStyle(isDone ? .secondary : .primary)
                if item.usedIn.count > 1 {
                    // 2つ以上のレシピで使う材料は、合算されていることが分かるようにする。
                    Text(item.usedIn.joined(separator: "・"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(item.quantityText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func toggle(_ item: ShoppingItem) {
        var purchased = plan.purchasedIngredientIDs
        if purchased.contains(item.id) {
            purchased.remove(item.id)
        } else {
            purchased.insert(item.id)
        }
        plan.purchasedIngredientIDs = purchased
    }
}
