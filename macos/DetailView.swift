import SwiftUI

struct DetailView: View {
  @ObservedObject var model: PickerModel
  let detail: GlyphDetail
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          Text(detail.record.symbol).font(.system(size: 54))
          Spacer()
          Button {
            model.detail = nil
          } label: {
            Image(systemName: "xmark")
          }.help("Close details")
        }
        Text(detail.record.name).font(.headline).textSelection(.enabled)
        Text(detail.classification).font(.caption).foregroundStyle(.secondary)
        ForEach(detail.components, id: \.self) {
          Text($0).font(.caption.monospaced()).textSelection(.enabled)
        }
        Text("Your words").font(.headline)
        ForEach(detail.aliases) { alias in
          HStack {
            Text(alias.term + (alias.type == "provisional" ? " (provisional)" : ""))
            Spacer()
            Button("Forget") { model.learn("unlearn", term: alias.term) }
          }
        }
        HStack {
          TextField("Teach a word", text: $model.term).onSubmit {
            model.learn("teach", term: model.term)
          }
          Button("Teach") { model.learn("teach", term: model.term) }
        }
        Text(detail.keywords.joined(separator: ", ")).font(.caption).textSelection(.enabled)
        if detail.variants.count > 1 {
          Text("Variants").font(.headline)
          FlowSymbols(symbols: detail.variants) { model.pick(detail.record, symbol: $0) }
        }
        ForEach(detail.values) { row in
          VStack(alignment: .leading, spacing: 3) {
            Text(row.label).font(.caption).foregroundStyle(.secondary)
            Button {
              PickerModel.copy(row.value)
              model.message = "Copied \(row.label)"
            } label: {
              Text(row.value).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .multilineTextAlignment(.leading)
            }.buttonStyle(.plain).help("Copy \(row.label)")
          }
        }
        ForEach(detail.notes, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
        related("Twins", detail.twins)
        related("Related", detail.related)
        if !detail.contexts.isEmpty {
          Text("Show in category").font(.headline)
          ForEach(detail.contexts) { category in
            Menu(category.title) {
              Button("Show in category") {
                model.query = ""
                model.category = category.id
                model.detail = nil
              }
              Button("Use this glyph as category icon") {
                model.setIcon(category, symbol: detail.record.symbol)
              }
              Button("Reset category icon") { model.setIcon(category, symbol: nil) }
            }
          }
        }
        Link(
          "Wikipedia",
          destination: URL(
            string: "https://en.wikipedia.org/w/index.php?search=" + detail.record.name
              .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!)
        Link(
          "codepoints.net",
          destination: URL(
            string: "https://codepoints.net/U+"
              + detail.record.hexseq.components(separatedBy: " ")[0])!)
        Link(
          "unicode.org",
          destination: URL(
            string: "https://util.unicode.org/UnicodeJsps/character.jsp?a="
              + detail.record.hexseq.components(separatedBy: " ")[0])!)
      }.padding(16)
    }
  }
  @ViewBuilder private func related(_ title: String, _ glyphs: [Glyph]) -> some View {
    if !glyphs.isEmpty {
      Text(title).font(.headline)
      ScrollView(.horizontal) {
        HStack {
          ForEach(Array(glyphs.enumerated()), id: \.offset) { _, glyph in
            Button(glyph.symbol) { model.inspect(glyph) }.font(.title).help(glyph.name)
          }
        }
      }
    }
  }
}
struct FlowSymbols: View {
  let symbols: [String]
  let action: (String) -> Void
  var body: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 38))]) {
      ForEach(symbols, id: \.self) { symbol in Button(symbol) { action(symbol) }.font(.title2) }
    }
  }
}
