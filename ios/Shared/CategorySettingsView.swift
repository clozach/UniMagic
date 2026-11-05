import SwiftUI

struct CategorySettingsView: View {
    @ObservedObject var model: PickerModel
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    private var filtered: [BrowseCategory] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.categories.filter { term.isEmpty || ($0.title + " " + $0.sourceLabel).localizedCaseInsensitiveContains(term) }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
            CategoryFilterField(query: $query)
            Divider()
            List {
                if Bundle.main.bundleIdentifier == "com.clozach.unimagic" { PairedMacUpdateSettings() }
                Section {
                    Text(model.canEditCategoryVisibility
                         ? "Choose categories for browsing. Symbol changes stay in this app; the keyboard keeps its own symbols and history."
                         : "Choose visible categories in the app. Symbol changes and history stay in this keyboard.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("\(filtered.count) categories") {
                    ForEach(filtered) { category in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                CategoryLabelView(category: category)
                                CategorySamplesView(model: model, categoryID: category.id).padding(.leading, 62)
                            }.padding(.vertical, 4)
                            Toggle("Show \(category.title)", isOn: Binding(get: {
                                model.preferences.categoryVisibility[category.id] ?? category.defaultEnabled
                            }, set: { model.setCategoryEnabled(category.id, enabled: $0) }))
                                .labelsHidden().fixedSize().disabled(!model.canEditCategoryVisibility)
                                .accessibilityLabel("Show \(category.title), \(category.sourceLabel)")
                                .accessibilityIdentifier("category-enabled-" + category.id)
                        }.accessibilityElement(children: .contain)
                        NavigationLink {
                            CategorySymbolSettings(model: model, categoryID: category.id)
                        } label: {
                            Text("Category symbol").font(.subheadline).padding(.leading, 62)
                        }.accessibilityIdentifier("category-symbol-settings-" + category.id)
                    }
                }
                if filtered.isEmpty { Text("No matching categories").foregroundStyle(.secondary) }
            }.accessibilityIdentifier("category-settings-list")
            }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if Bundle.main.bundleIdentifier == "com.clozach.unimagic" { AppVersionCorner().background(.bar) }
                }
                .navigationTitle(Bundle.main.bundleIdentifier == "com.clozach.unimagic" ? "Settings" : "Categories").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("category-settings-done") } }
        }
    }
}

private struct CategorySymbolSettings: View {
    @ObservedObject var model: PickerModel
    let categoryID: String
    private var category: BrowseCategory? { model.categories.first { $0.id == categoryID } }
    var body: some View {
        Form {
            if let category {
                Section {
                    CategoryLabelView(category: category)
                    Text("Hold a character, then choose Use as category symbol to change this symbol.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("Original symbol") {
                    CategoryResetDefaultButton(category: category) { model.setCategoryExemplar(category.id, exemplar: nil) }
                        .disabled(category.exemplarOverride == nil)
                    Text(category.exemplarOverride == nil ? "Using the original symbol." : "Using your symbol in this app.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.navigationTitle("Category symbol").navigationBarTitleDisplayMode(.inline)
    }
}

private struct CategorySamplesView: View {
    @ObservedObject var model: PickerModel
    let categoryID: String
    @State private var samples: [BrowseOccurrence] = []
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<6) { index in
                Group {
                    if samples.indices.contains(index) {
                        let glyph = samples[index].glyph
                        Text(GlyphDisplay.label(glyph)).font(.system(size: 22))
                            .lineLimit(1).minimumScaleFactor(0.2).accessibilityLabel(glyph.name)
                    } else { Color.clear.accessibilityHidden(true) }
                }.frame(maxWidth: .infinity).frame(height: 30)
            }
        }.task(id: categoryID) { samples = await model.samples(for: categoryID) }
            .accessibilityElement(children: .ignore).accessibilityLabel(samples.isEmpty ? "" : "Sample: " + samples.map { $0.glyph.name }.joined(separator: ", "))
    }
}
