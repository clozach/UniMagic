import UIKit
import SwiftUI

struct KeyboardRoot: View {
    @ObservedObject var model: PickerModel
    let insert: (String) -> Void
    let delete: () -> Void
    let globe: (UIButton, UIEvent) -> Void
    let showGlobe: Bool
    @State private var mode = KeyboardMode.browse
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var controlHeight: CGFloat { verticalSizeClass == .compact ? 32 : 44 }
    private var queryKeyHeight: CGFloat { verticalSizeClass == .compact ? 28 : 40 }
    private var searching: Bool { if case .search = mode { return true }; return false }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    modeButton("Browse characters", image: "square.grid.2x2", selected: !searching, identifier: "keyboard-browse") { model.query = ""; mode = .browse }
                    modeButton("Search characters", image: "magnifyingglass", selected: searching, identifier: "keyboard-search") { mode = .search(.letters) }
                    modeButton("Back to previous view", image: "arrow.uturn.backward", selected: false, identifier: "keyboard-context-back") { model.returnFromContext() }
                        .opacity(model.canReturnFromContext ? 1 : 0).disabled(!model.canReturnFromContext)
                        .accessibilityHidden(!model.canReturnFromContext)
                    Spacer(minLength: 0)
                }.padding(.top, 4).frame(width: 44)
                Divider()
                VStack(spacing: 0) {
                    if searching {
                        HStack(spacing: 0) {
                            ScrollViewReader { proxy in
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 0) {
                                        Text(model.query.isEmpty ? "Search characters" : model.query)
                                            .font(.subheadline).fixedSize().frame(minHeight: controlHeight)
                                        Color.clear.frame(width: 1, height: 1).id("query-end")
                                    }
                                }.modifier(KeyboardScrollEdges()).onChange(of: model.query) { _, _ in proxy.scrollTo("query-end", anchor: .trailing) }
                            }.accessibilityIdentifier("keyboard-query")
                            Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: controlHeight) }.accessibilityLabel("Clear search").accessibilityIdentifier("keyboard-clear-search")
                        }.padding(.leading, 8).frame(height: controlHeight)
                    }
                    GlyphPicker(model: model, keyboard: true, showsKeyboardCategories: !searching, onBrowse: { mode = .browse }, destination: insert)
                        .environment(\.keyboardSearchMode, searching)
                    if case .search(let layout) = mode { queryKeys(layout) }
                }
            }
            HStack(spacing: 4) {
                if showGlobe { GlobeKey(action: globe).frame(width: 44, height: controlHeight) }
                if case .search(let layout) = mode {
                Button(layout == .letters ? "123" : "ABC") { mode = .search(layout == .letters ? .symbols : .letters) }.frame(minWidth: 44, minHeight: controlHeight)
                Button("Space") { model.query += " " }.frame(maxWidth: .infinity, minHeight: controlHeight)
                Button { if !model.query.isEmpty { model.query.removeLast() } } label: { Image(systemName: "delete.left").frame(width: 44, height: controlHeight) }.accessibilityLabel("Delete search letter")
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        Text(model.message.isEmpty ? "Tap to insert · Hold for details" : model.message)
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: controlHeight)
                    }.modifier(KeyboardScrollEdges()).frame(height: controlHeight).accessibilityIdentifier("glyph-status")
                }
                Button { delete() } label: { Label("Text", systemImage: "delete.left").font(.caption).frame(width: 60, height: controlHeight) }.accessibilityLabel("Delete from your text")
            }.padding(.horizontal, 4)
        }.background(Color(uiColor: .systemBackground))
            .onChange(of: model.navigationTarget?.id) { _, target in if target != nil { mode = .browse } }
            .onChange(of: model.query) { _, query in if !query.isEmpty && !searching { mode = .search(.letters) } }
    }
    private func modeButton(_ title: String, image: String, selected: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image).font(.system(size: 19, weight: .medium))
                .frame(width: 44, height: controlHeight)
                .contentShape(Rectangle())
                .background(selected ? Color.accentColor.opacity(0.14) : Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).foregroundStyle(selected ? Color.accentColor : Color.secondary)
            .accessibilityLabel(title).accessibilityIdentifier(identifier).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func queryKeys(_ layout: KeyboardKeyLayout) -> some View {
        ForEach(layout == .symbols ? ["1234567890", "+-=<>/\\:;", "!?@#$%&*()"] : ["qwertyuiop", "asdfghjkl", "zxcvbnm"], id: \.self) { row in
            HStack(spacing: 2) {
                ForEach(Array(row).map(String.init), id: \.self) { key in
                    Button(key) { model.query += key }.frame(maxWidth: .infinity, minHeight: queryKeyHeight)
                        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 5))
                }
            }.padding(.horizontal, 4)
        }
    }
}

private enum KeyboardKeyLayout { case letters, symbols }
private enum KeyboardMode { case browse, search(KeyboardKeyLayout) }
private struct KeyboardSearchModeKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var keyboardSearchMode: Bool {
        get { self[KeyboardSearchModeKey.self] }
        set { self[KeyboardSearchModeKey.self] = newValue }
    }
}

struct GlobeKey: UIViewRepresentable {
    let action: (UIButton, UIEvent) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "globe"), for: .normal)
        button.accessibilityLabel = "Next keyboard"
        button.addTarget(context.coordinator, action: #selector(Coordinator.pressed(_:event:)), for: .allTouchEvents)
        return button
    }
    func updateUIView(_ uiView: UIButton, context: Context) {}
    final class Coordinator: NSObject {
        let action: (UIButton, UIEvent) -> Void
        init(action: @escaping (UIButton, UIEvent) -> Void) { self.action = action }
        @objc func pressed(_ sender: UIButton, event: UIEvent) { action(sender, event) }
    }
}
