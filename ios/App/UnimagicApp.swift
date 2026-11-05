import SwiftUI
import UIKit

@main struct UnimagicApp: App {
    @StateObject private var model = PickerModel()
    @State private var openRequest = 0
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                VStack(spacing: 0) {
                    UnimagicSearchBar(model: model).id(openRequest)
                    GlyphPicker(model: model, host: .standaloneApp) { UIPasteboard.general.string = $0 }
                }.navigationTitle("UniMagic").navigationBarTitleDisplayMode(.inline)
            }.onOpenURL { url in
                guard url.scheme == "unimagic", url.host == "picker" else { return }
                model.help = false; model.detail = nil
                openRequest += 1
            }
        }
    }
}
