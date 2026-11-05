import SwiftUI

struct GlyphRow: View {
    @ObservedObject var model: PickerModel
    let items: [PickerGlyphItem]
    let columns: Int
    let host: PickerHost
    let destination: (String) -> Void
    init(model: PickerModel, items: [PickerGlyphItem], columns: Int, host: PickerHost, destination: @escaping (String) -> Void) {
        self.model = model; self.items = items; self.columns = columns; self.host = host; self.destination = destination
    }
    init(model: PickerModel, glyphs: [Glyph], columns: Int, host: PickerHost, destination: @escaping (String) -> Void) {
        self.init(model: model, items: glyphs.map(PickerGlyphItem.search), columns: columns, host: host, destination: destination)
    }
    var body: some View {
        HStack(spacing: 4) {
            ForEach(items) { item in
                let glyph = item.glyph
                Button { model.picked(item, destination: destination, feedback: host.inserts ? "Inserted" : "Copied") } label: {
                    Text(GlyphDisplay.label(glyph))
                        .font(GlyphDisplay.label(glyph) == glyph.symbol || GlyphDisplay.label(glyph).hasPrefix("◌") ? .system(size: 30) : .caption)
                        .lineLimit(1).minimumScaleFactor(0.15)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.isLoading && !model.query.isEmpty)
                .accessibilityLabel(glyph.name)
                .accessibilityIdentifier("glyph-" + glyph.id)
                .accessibilityHint(host.inserts ? "Inserts character" : "Copies character")
                .accessibilityAction(named: Text("Details")) { model.openDetails(item) }
                .highPriorityGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in model.openDetails(item) })
            }
            ForEach(0..<max(0, columns - items.count), id: \.self) { _ in
                Color.clear.frame(maxWidth: .infinity, minHeight: 48).accessibilityHidden(true)
            }
        }.accessibilityElement(children: .contain)
    }
}
