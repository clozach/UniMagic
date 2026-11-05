import SwiftUI

struct GlyphPicker: View {
    @ObservedObject var model: PickerModel
    let host: PickerHost
    let destination: (String) -> Void
    let onBrowse: () -> Void
    let showsKeyboardCategories: Bool
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    init(model: PickerModel, host: PickerHost, showsKeyboardCategories: Bool = true, onBrowse: @escaping () -> Void = {}, destination: @escaping (String) -> Void) {
        self.model = model; self.host = host; self.destination = destination; self.onBrowse = onBrowse
        self.showsKeyboardCategories = showsKeyboardCategories
    }
    init(model: PickerModel, keyboard: Bool, showsKeyboardCategories: Bool = true, onBrowse: @escaping () -> Void = {}, destination: @escaping (String) -> Void) {
        self.init(model: model, host: keyboard ? .keyboard : .standaloneApp, showsKeyboardCategories: showsKeyboardCategories, onBrowse: onBrowse, destination: destination)
    }
    var body: some View {
        Group {
            if host.inserts {
                VStack(spacing: 0) {
                    KeyboardGlyphGrid(model: model, host: host, destination: destination)
                    if showsKeyboardCategories { CategoryStrip(model: model, onSelection: onBrowse) }
                }
            } else {
                appLayout
            }
        }
        .background(CategorySwipe { model.cycleCategory(forward: $0); onBrowse() })
        .sheet(item: $model.detailSelection) { item in GlyphDetails(model: model, item: item, host: host, destination: destination).id(item.id) }
        .sheet(isPresented: $model.help) { PickerHelp(host: host) }
        .sheet(isPresented: $model.settings) { CategorySettingsView(model: model) }
    }
    private var appTools: some View {
        HStack {
            Button { model.returnFromContext() } label: {
                Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44)
            }.accessibilityLabel("Back to previous view").accessibilityIdentifier("app-context-back")
                .opacity(model.canReturnFromContext ? 1 : 0).disabled(!model.canReturnFromContext)
                .accessibilityHidden(!model.canReturnFromContext)
            Spacer(minLength: 4)
            Button { model.settings = true } label: {
                Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
            }.accessibilityLabel("Category settings").accessibilityIdentifier("category-settings")
            Button { model.help = true } label: { Image(systemName: "questionmark.circle").frame(width: 44, height: 44) }
                .accessibilityLabel("Help")
        }.frame(height: 44)
    }
    private var appLayout: some View {
        let compact = verticalSizeClass == .compact
        // AnyLayout keeps the table and its scroll anchor alive across rotation.
        let layout = compact ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        return layout {
            appTools.padding(.horizontal, 12).frame(width: compact ? 180 : nil)
            IndexedGlyphBrowser(model: model, host: host, destination: destination)
            appStatus(compact: compact).frame(width: compact ? 180 : nil)
        }
        .toolbar(compact && host == .standaloneApp ? .hidden : .automatic, for: .navigationBar)
    }
    @ViewBuilder private func appStatus(compact: Bool) -> some View {
        if compact {
            VStack(spacing: 0) {
                Text(model.message).font(.caption).lineLimit(2).frame(height: 32)
                    .accessibilityIdentifier("glyph-status")
                Button("Undo learning") { model.undo() }.disabled(!model.canUndo).frame(minHeight: 44)
            }.padding(.horizontal, 12)
        } else {
            HStack {
                Text(model.message).font(.caption).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("glyph-status")
                Spacer()
                Button("Undo learning") { model.undo() }.disabled(!model.canUndo).frame(minHeight: 44)
            }.padding(.horizontal, 12).frame(minHeight: 64)
        }
    }
}
