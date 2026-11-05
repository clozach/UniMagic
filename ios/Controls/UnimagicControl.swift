import SwiftUI
import WidgetKit

struct UnimagicControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.clozach.unimagic.search") {
            ControlWidgetButton(action: OpenUnimagic()) {
                Label("Unimagic", systemImage: "character.magnify")
            }
        }
        .displayName("Unimagic")
        .description("Find and copy a symbol.")
    }
}

@main
struct UnimagicControls: WidgetBundle {
    var body: some Widget { UnimagicControl() }
}
