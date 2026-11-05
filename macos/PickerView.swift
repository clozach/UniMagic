import SwiftUI

struct PickerView: View {
  @ObservedObject var model: PickerModel
  @FocusState private var searchFocused: Bool
  private let columns = Array(repeating: GridItem(.fixed(64), spacing: 8), count: 8)
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField("Search words, symbols, or U+…", text: $model.query).textFieldStyle(.plain).font(
          .title3
        ).focused($searchFocused)
          .onSubmit {
            model.pick(opposite: NSApp.currentEvent?.modifierFlags.contains(.shift) == true)
          }
        Button {
          model.showingSettings.toggle()
        } label: {
          Image(systemName: "gearshape")
        }.help("Settings")
      }.padding(16)
      Divider()
      HStack(spacing: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: 4) {
            if model.categories.first(where: { $0.id == "utility:recents" })?.enabled ?? true {
              categoryButton("Recents", "recents")
            }
            if model.categories.first(where: { $0.id == "utility:frequent" })?.enabled ?? true {
              categoryButton("Frequently used", "frequent")
            }
            ForEach(model.categories.filter { $0.enabled && !$0.id.hasPrefix("utility:") }) {
              category in categoryButton(category.title, category.id, category: category)
            }
          }.padding(8)
        }.frame(width: 190).background(Color(nsColor: .controlBackgroundColor))
        ScrollViewReader { proxy in
          ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
              ForEach(model.glyphs) { glyph in
                Button {
                  model.selected = glyph.id
                  model.pick(glyph)
                } label: {
                  GlyphSymbol(glyph: glyph).frame(width: 62, height: 58).contentShape(Rectangle())
                    .background(
                      model.selected == glyph.id ? Color.accentColor.opacity(0.22) : Color.clear,
                      in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).help(glyph.name).accessibilityLabel(glyph.name).id(glyph.id)
                  .overlay(alignment: .topTrailing) {
                    Button {
                      model.inspect(glyph)
                    } label: {
                      Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 18).contentShape(Rectangle())
                    }.buttonStyle(.plain).help("Details for " + glyph.name).accessibilityLabel(
                      "Details for " + glyph.name)
                  }
                  .contextMenu {
                    Button("Insert") { model.pick(glyph) }
                    Button("Copy") { model.pick(glyph, copy: true) }
                    Button("Details") { model.inspect(glyph) }
                  }
              }
            }.padding(12)
            Button("Load more") { model.more() }.disabled(!model.canLoadMore).padding(.bottom, 12)
          }.onChange(of: model.selected) { _, value in
            if let value { proxy.scrollTo(value, anchor: .center) }
          }
        }.frame(minWidth: 590)
        Divider()
        Group {
          if let detail = model.detail {
            DetailView(model: model, detail: detail)
          } else {
            Text("Open details with › or Tab").foregroundStyle(.secondary).frame(
              maxWidth: .infinity, maxHeight: .infinity)
          }
        }.frame(width: 330)
      }
      Divider()
      HStack {
        Text(model.message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        Spacer()
        Toggle("Keep open", isOn: $model.keepOpen).toggleStyle(.checkbox)
        Button("Copy") { model.pick(copy: true) }.keyboardShortcut(
          "c", modifiers: [.command, .shift])
        Button("Insert ↩") { model.pick() }.keyboardShortcut(.return, modifiers: [])
      }.padding(12).frame(height: 48)
    }.frame(minWidth: 1120, minHeight: 580).background(Color(nsColor: .windowBackgroundColor))
      .onAppear { searchFocused = true }
      .onMoveCommand { direction in
        switch direction {
        case .left: model.move(-1)
        case .right: model.move(1)
        case .up: model.move(-8)
        case .down: model.move(8)
        default: break
        }
      }
      .onExitCommand {
        if model.detail != nil {
          model.detail = nil
          searchFocused = true
        } else {
          model.dismiss?()
        }
      }
      .sheet(isPresented: $model.showingSettings) { SettingsView(model: model) }
  }
  private func categoryButton(_ title: String, _ id: String, category: Category? = nil) -> some View
  {
    Button {
      model.category = id
    } label: {
      HStack(spacing: 6) {
        if let icon = category?.icon {
          Text(icon).frame(width: 18)
        } else if let icon = category?.systemIcon {
          Image(systemName: icon).frame(width: 18)
        }
        Text(title).lineLimit(1)
      }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).frame(height: 30)
        .contentShape(Rectangle()).background(
          model.category == id ? Color.accentColor.opacity(0.18) : Color.clear,
          in: RoundedRectangle(cornerRadius: 6))
    }.buttonStyle(.plain).help(title).contextMenu {
      if let category { Button("Reset category icon") { model.setIcon(category, symbol: nil) } }
    }
  }

}
