import SwiftUI

struct UnimagicSearchBar: View {
    @ObservedObject var model: PickerModel
    @FocusState private var focused: Bool
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search characters", text: $model.query)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search).onSubmit { focused = false }
                .accessibilityIdentifier("glyph-search").focused($focused)
            Button { model.query = "" } label: {
                Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
            }.accessibilityLabel("Clear search").disabled(model.query.isEmpty)
        }.padding(.leading, 16).padding(.trailing, 4)
            .task { focused = true }
    }
}

enum PickerHost {
    case standaloneApp, keyboard, agentAlerts
    var inserts: Bool { self == .keyboard }
}
