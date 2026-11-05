import AppIntents

enum UnimagicDestination: String, AppEnum {
    case search
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Unimagic"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [.search: "Search"]
}

struct OpenUnimagic: OpenIntent {
    static var title: LocalizedStringResource = "Open Unimagic"
    @Parameter(title: "Destination") var target: UnimagicDestination
    init() { target = .search }
}

struct UnimagicShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenUnimagic(), phrases: ["Open \(.applicationName)"],
                    shortTitle: "Unimagic", systemImageName: "character.magnify")
    }
}
