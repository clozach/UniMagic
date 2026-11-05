import SwiftUI

struct GlyphDetails: View {
    @ObservedObject var model: PickerModel
    let item: PickerGlyphItem
    private var glyph: Glyph { item.glyph }
    let host: PickerHost
    let destination: (String) -> Void
    @State private var word = ""
    @State private var categoryRoute: GlyphCategoryRoute?
    @State private var contexts: [BrowseContextTarget] = []
    @State private var chosenSymbolCategoryID: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { model.picked(item, destination: destination, feedback: host.inserts ? "Inserted" : "Copied") } label: {
                        HStack(spacing: 12) {
                            Text(GlyphDisplay.label(glyph)).font(.largeTitle).lineLimit(1).minimumScaleFactor(0.2).frame(width: 52)
                            Text(glyph.name).fixedSize(horizontal: false, vertical: true)
                        }
                    }.frame(minHeight: 44).accessibilityIdentifier("detail-pick-character")
                    Text(glyph.id.uppercased()).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                }
                GlyphCategoryActions(model: model, item: item, targets: contexts, chosenSymbolCategoryID: chosenSymbolCategoryID,
                                     route: $categoryRoute, assignSymbol: assignSymbol)
                if glyph.skinModifiable {
                    Section("Skin tone") {
                        ViewThatFits {
                            HStack { toneButtons }
                            VStack { toneButtons }
                        }
                    }
                }
                Section("Encodings") {
                    LabeledContent("Code points", value: glyph.symbol.unicodeScalars.map { "U+" + String($0.value, radix: 16).uppercased() }.joined(separator: " "))
                    LabeledContent("HTML", value: glyph.entities.isEmpty ? glyph.symbol.unicodeScalars.map { "&#" + String($0.value) + ";" }.joined() : glyph.entities.joined(separator: " "))
                    LabeledContent("UTF-8", value: glyph.symbol.utf8.map { String(format: "%02X", $0) }.joined(separator: " "))
                }.textSelection(.enabled)
                if !glyph.twins.isEmpty { Section("Twins") { relatives(glyph.twins) } }
                if !glyph.related.isEmpty { Section("Related") { relatives(glyph.related) } }
                Section("Teach a word") {
                    if host.inserts {
                        Text(model.query.isEmpty ? "Type a search before opening details to teach it." : model.query)
                        Button("Teach this search") { model.teach(model.query, glyph: glyph) }.disabled(model.query.isEmpty)
                    } else {
                        TextField("Word or phrase", text: $word).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("Teach") { model.teach(word, glyph: glyph); word = "" }.disabled(word.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    ForEach(model.learnedWords(glyph), id: \.self) { term in
                        HStack { Text(term); Spacer(); Button("Forget") { model.forget(term, glyph: glyph) } }
                    }
                    Button("Undo learning change") { model.undo() }.disabled(!model.canUndo)
                    Text(model.message).font(.caption).foregroundStyle(.secondary)
                }
            }.accessibilityIdentifier("glyph-detail-form").navigationTitle("Character").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.task(id: item.id) {
            let values = await model.contexts(for: glyph, origin: item.origin)
            if !Task.isCancelled { contexts = values }
        }
            .sheet(item: $categoryRoute) { route in
                CategoryDestinationPicker(title: route.id == "context" ? "Show in category" : "Use as category symbol",
                                          categories: destinationCategories(route)) { category in
                    switch route {
                    case .context(let targets):
                        if let target = targets.first(where: { $0.categoryID == category.id }) { model.showInCategory(target) }
                    case .symbol: assignSymbol(category)
                    }
                }
            }
    }
    private func destinationCategories(_ route: GlyphCategoryRoute) -> [BrowseCategory] {
        if case .context(let targets) = route {
            let ids = Set(targets.map(\.categoryID)); return model.categories.filter { ids.contains($0.id) }
        }
        return model.categories
    }
    private func assignSymbol(_ category: BrowseCategory) {
        chosenSymbolCategoryID = category.id
        let scalars = glyph.symbol.unicodeScalars
        let emoji = scalars.contains { $0.value == 0xFE0F } || (!scalars.contains { $0.value == 0xFE0E } && scalars.contains { $0.properties.isEmojiPresentation })
        model.setCategoryExemplar(category.id, exemplar: emoji ? .emoji(glyph.symbol) : .unicode(glyph.symbol))
    }
    private func relatives(_ ids: [String]) -> some View {
        ForEach(ids, id: \.self) { id in
            if let relative = model.glyph(id) {
                Button { model.openDetails(.search(relative)) } label: {
                    HStack(spacing: 12) {
                        Text(GlyphDisplay.label(relative)).lineLimit(1).minimumScaleFactor(0.2).frame(width: 44)
                        Text(relative.name).fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(minHeight: 44).accessibilityIdentifier("detail-relative-" + id)
            }
        }
    }
    private var toneButtons: some View {
        ForEach(0..<6) { tone in
            Button { model.picked(glyph, symbol: tone == 0 ? glyph.symbol : glyph.skinVariant(tone: tone), destination: destination, feedback: host.inserts ? "Inserted" : "Copied") } label: {
                Text(tone == 0 ? glyph.symbol : glyph.skinVariant(tone: tone)).font(.title2).frame(minWidth: 44, minHeight: 44)
            }.buttonStyle(.borderless)
                .accessibilityLabel(tone == 0 ? "Default tone" : "Skin tone \(tone)")
        }
    }
}
