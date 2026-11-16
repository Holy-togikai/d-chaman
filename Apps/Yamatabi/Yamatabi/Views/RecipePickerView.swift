import SwiftUI

/// レシピを選ぶ画面。持っている器具や手間で絞り込めます。
struct RecipePickerView: View {
    let selected: [Recipe]
    let onDone: ([Recipe]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<String> = []
    @State private var gearFilter: Set<CookingGear> = []
    @State private var hidesCooler = false

    private var results: [Recipe] {
        RecipeData.all.filter { recipe in
            let gearOK = gearFilter.isEmpty || recipe.gear.allSatisfy { gearFilter.contains($0) }
            let coolerOK = !hidesCooler || !recipe.needsCooler
            return gearOK && coolerOK
        }
    }

    var body: some View {
        NavigationStack {
            List {
                filterSection

                Section {
                    ForEach(results) { recipe in
                        Button {
                            toggle(recipe)
                        } label: {
                            row(recipe)
                        }
                        .tint(.primary)
                    }
                } header: {
                    Text("\(results.count) 品")
                } footer: {
                    Text("レシピは山で作ることを前提に書き下ろしたものです。"
                         + "火加減や時間は目安なので、様子を見ながら調整してください。")
                }
            }
            .navigationTitle("レシピを選ぶ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("決定") {
                        onDone(RecipeData.all.filter { chosen.contains($0.id) })
                        dismiss()
                    }
                }
            }
            .overlay {
                if results.isEmpty {
                    EmptyStateView(
                        title: "条件に合うレシピがありません",
                        message: "器具の絞り込みをゆるめてみてください。",
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                }
            }
            .onAppear { chosen = Set(selected.map(\.id)) }
        }
    }

    private var filterSection: some View {
        Section {
            ForEach(CookingGear.allCases) { gear in
                Toggle(isOn: gearBinding(for: gear)) {
                    Label(gear.rawValue, systemImage: gear.symbolName)
                }
                .font(.subheadline)
            }
            Toggle("要保冷のレシピを隠す", isOn: $hidesCooler)
                .font(.subheadline)
        } header: {
            Text("持っていく器具")
        } footer: {
            Text("何も選ばないと、すべてのレシピを出します。"
                 + "選ぶと、その器具だけで作れるレシピに絞られます。")
        }
    }

    private func row(_ recipe: Recipe) -> some View {
        let isChosen = chosen.contains(recipe.id)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isChosen ? Color.brandGreen : .secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.name).font(.body.weight(.medium))
                Text(recipe.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Label("\(recipe.cookingMinutes)分", systemImage: "clock")
                    Text("手間 \(recipe.effortText)")
                    if recipe.needsCooler {
                        Label("要保冷", systemImage: "snowflake").foregroundStyle(.blue)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                Text(recipe.gearText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }

    private func gearBinding(for gear: CookingGear) -> Binding<Bool> {
        Binding(
            get: { gearFilter.contains(gear) },
            set: { isOn in
                if isOn { gearFilter.insert(gear) } else { gearFilter.remove(gear) }
            }
        )
    }

    private func toggle(_ recipe: Recipe) {
        if chosen.contains(recipe.id) {
            chosen.remove(recipe.id)
        } else {
            chosen.insert(recipe.id)
        }
    }
}

/// レシピの詳細。材料は選んだ人数ぶんに換算して出します。
struct RecipeDetailView: View {
    let recipe: Recipe
    let servings: Int

    private var multiplier: Double {
        Double(servings) / Double(max(1, recipe.servings))
    }

    var body: some View {
        List {
            Section {
                Text(recipe.summary)
                    .font(.callout)
                LabeledContent("調理時間", value: "\(recipe.cookingMinutes) 分")
                LabeledContent("手間", value: recipe.effortText)
                LabeledContent("器具", value: recipe.gearText)
                if recipe.needsCooler {
                    Label("要保冷", systemImage: "snowflake").foregroundStyle(.blue)
                }
            }

            Section("材料（\(servings)人ぶん）") {
                ForEach(recipe.ingredients) { ingredient in
                    Text(ingredient.text(multiplier: multiplier))
                }
            }

            Section("作り方") {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.brandGreen)
                            .frame(width: 18)
                        Text(step).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Section("ひとこと") {
                Text(recipe.tips).font(.callout)
            }
        }
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
