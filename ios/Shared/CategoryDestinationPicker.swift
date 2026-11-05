import SwiftUI

/// Shared by context navigation and symbol assignment; IDs keep duplicate human titles distinct.
struct CategoryDestinationPicker: View {
    let title: String
    let categories: [BrowseCategory]
    let selection: (BrowseCategory) -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    private var filtered: [BrowseCategory] {
        categories.filter { query.isEmpty || ($0.title + " " + $0.sourceLabel).localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
            CategoryFilterField(query: $query)
            Divider()
            List {
                ForEach(filtered) { category in
                    Button { selection(category); dismiss() } label: { CategoryLabelView(category: category) }
                        .accessibilityIdentifier("category-destination-" + category.id)
                }
                if filtered.isEmpty { Text("No matching categories").foregroundStyle(.secondary) }
            }.accessibilityIdentifier("category-destination-list")
            }
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

/// Reserve its size while focused; iOS search presentation otherwise hides sheet actions.
struct CategoryFilterField: View {
    @Binding var query: String
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find categories", text: $query).focused($focused)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.done).onSubmit { focused = false }
                .accessibilityIdentifier("category-filter")
            Button { query = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                .accessibilityLabel("Clear category search").disabled(query.isEmpty)
        }.padding(.leading, 16).padding(.trailing, 4).frame(height: 44)
    }
}
