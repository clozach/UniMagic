import SwiftUI
import Foundation

struct PickerEnvironment {
    let databaseURL: URL?
    let directory: URL
    let seedURL: URL?
    static func production() -> Self {
        Self(databaseURL: Bundle.main.url(forResource: "corpus", withExtension: "sqlite"),
             directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
             seedURL: nil)
    }
}

@MainActor final class PickerModel: ObservableObject {
    enum Library { case starting, ready, failed(String) }
    enum Search { case idle, loading([Glyph]), ready([Glyph]) }
    enum Presentation { case none, help, settings, detail(PickerGlyphItem) }
    struct State {
        var library: Library = .starting
        var searchRevision = 0
        var search: Search = .idle { didSet { searchRevision &+= 1 } }
        var presentation: Presentation = .none
        var categories: [BrowseCategory] = []
        var enabled: [BrowseCategory] = []
        var preferences = BrowsePreferences(catalogueRevision: "")
        var sectionsRevision = 0
        var sections: [PickerBrowseSection] = [] { didSet { sectionsRevision &+= 1 } }
        var selectedCategoryID = "set:Emojis"
        var navigation: BrowseNavigationTarget?
        var searchNavigation: PickerSearchNavigationTarget?
        var message = ""
        var inspecting = false
        var canEditVisibility = false
        var learning = LearningStore()
        var undo: LearningStore?
        var glyphCache: [String: Glyph] = [:]
    }
    @Published private var state = State()
    @Published var query = "" { didSet { if query != oldValue { refresh() } } }
    var data: State { state }
    func change(_ body: (inout State) -> Void) { body(&state) }
    let worker: PickerSearchWorker?
    let historyHost: HistoryHost
    let storageURL: URL
    var persistenceError: String?
    var searchGeneration = 0
    var pageGenerations: [String: Int] = [:]
    var visibleCategoryIDs: Set<String> = []
    var sectionTouches: [String: Int] = [:]
    var touchClock = 0
    var browsingUsage: [UsageEntry] = []
    var contextTarget: BrowseContextTarget?
    var contextGeneration = 0
    var cacheOrder: [String] = []
    var historyCursors: [String: [Int: BrowseCursor]] = [:]
    var historyFirstPages: [String: BrowsePage] = [:]
    var pickRevision = 0
    var utilityRevisions: [String: Int] = [:]
    var missingGlyphs: Set<String> = []
    var anchors: [String: String] = [:]
    struct ReturnLocation { let query: String; let categoryID: String; let anchor: BrowseOccurrence?; let context: BrowseContextTarget?; let searchGlyphID: String? }
    var returnLocations: [ReturnLocation] = []
    var glyphRequests: Set<String> = []

    init(environment: PickerEnvironment = .production(), historyHost: HistoryHost = .nativeApp, visibility: NativeVisibilityAccess? = nil) {
        self.historyHost = historyHost
        let legacyURL = environment.directory.appendingPathComponent("learning-v1.json")
        storageURL = legacyURL
        var legacyError: String?
        var saved = LearningStore()
        do {
            try FileManager.default.createDirectory(at: environment.directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: legacyURL.path) {
                saved = try JSONDecoder().decode(LearningStore.self, from: Data(contentsOf: legacyURL))
                guard saved.version == 1 else { throw NativeStoreError.unsupportedVersion(saved.version) }
            }
        } catch { legacyError = "Learning file unavailable. Existing data preserved."; saved = LearningStore() }
        if let url = environment.databaseURL {
            worker = PickerSearchWorker(databaseURL: url, directory: environment.directory, host: historyHost,
                                        visibility: visibility, legacyUsage: saved.usage, seedURL: environment.seedURL)
        } else { worker = nil }
        persistenceError = legacyError
        state.learning = saved
        browsingUsage = saved.usage
        if let error = persistenceError { state.message = error }
        guard let worker else { state.library = .failed("Glyph library unavailable"); state.message = "Glyph library unavailable"; return }
        worker.start { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let snapshot): self.apply(snapshot); self.change { $0.library = .ready }; self.ensureSectionLoaded(self.selectedCategoryID); self.refresh()
                case .failure(let error): self.change { $0.library = .failed(String(describing: error)); $0.message = String(describing: error) }
                }
            }
        }
    }

    var categories: [BrowseCategory] { state.categories }
    var enabledCategories: [BrowseCategory] { state.enabled }
    var selectedCategoryID: String { state.selectedCategoryID }
    var selectedCategory: BrowseCategory? { state.categories.first { $0.id == state.selectedCategoryID } }
    var category: String { selectedCategory?.title ?? "Emojis" }
    var sections: [PickerBrowseSection] { state.sections }
    var preferences: BrowsePreferences { state.preferences }
    var canEditCategoryVisibility: Bool { state.canEditVisibility }
    var navigationTarget: BrowseNavigationTarget? { state.navigation }
    var searchSelectionID: String? { state.searchNavigation?.glyphID }
    var searchNavigationTarget: PickerSearchNavigationTarget? { state.searchNavigation }
    var canReturnFromContext: Bool { !returnLocations.isEmpty }
    var message: String { get { state.message } set { change { $0.message = newValue } } }
    var inspecting: Bool { get { state.inspecting } set { change { $0.inspecting = newValue } } }
    var detailSelection: PickerGlyphItem? {
        get { if case .detail(let item) = state.presentation { return item }; return nil }
        set { change { if let item = newValue { $0.presentation = .detail(item) } else if case .detail = $0.presentation { $0.presentation = .none } } }
    }
    var detail: Glyph? { get { detailSelection?.glyph } set { detailSelection = newValue.map(PickerGlyphItem.search) } }
    var help: Bool {
        get { if case .help = state.presentation { return true }; return false }
        set { change { if newValue { $0.presentation = .help } else if case .help = $0.presentation { $0.presentation = .none } } }
    }
    var settings: Bool {
        get { if case .settings = state.presentation { return true }; return false }
        set { change { if newValue { $0.presentation = .settings } else if case .settings = $0.presentation { $0.presentation = .none } } }
    }
    var results: [Glyph] {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return state.sections.first { $0.id == selectedCategoryID }?.glyphs ?? [] }
        switch state.search { case .idle: return []; case .loading(let previous), .ready(let previous): return previous }
    }
    var isLoading: Bool {
        if case .starting = state.library { return true }
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { if case .loading = state.search { return true }; return false }
        guard let section = state.sections.first(where: { $0.id == selectedCategoryID }), section.items.isEmpty else { return false }
        switch section.load { case .more, .loading: return true; case .complete, .failed: return false }
    }
    var browseDestination: String? {
        get { state.navigation?.categoryID }
        set { change { $0.navigation = newValue.map { .section(UUID(), categoryID: $0) } } }
    }
    func refresh() {
        searchGeneration += 1
        change { $0.searchNavigation = nil }
        contextGeneration += 1
        let generation = searchGeneration
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { change { $0.search = .idle }; return }
        guard let worker else { return }
        let previous = results
        change { $0.search = .loading(previous) }
        worker.search(query: query, store: state.learning) { [weak self] glyphs in
            Task { @MainActor in
                guard let self, generation == self.searchGeneration else { return }
                self.change { $0.search = .ready(glyphs) }; self.cache(glyphs)
            }
        }
    }
    func glyph(_ id: String) -> Glyph? {
        if let cached = state.glyphCache[id] { return cached }
        guard !missingGlyphs.contains(id), let worker, glyphRequests.insert(id).inserted else { return nil }
        worker.glyphs([id]) { [weak self] glyphs in
            Task { @MainActor in
                guard let self else { return }
                self.glyphRequests.remove(id)
                if glyphs.isEmpty { self.missingGlyphs.insert(id) } else { self.cache(glyphs) }
            }
        }
        return nil
    }
    func openDetails(_ item: PickerGlyphItem) { detailSelection = item }
    func acknowledgeSearchNavigation(_ id: UUID) { if state.searchNavigation?.id == id { change { $0.searchNavigation = nil } } }
    func acknowledgeNavigation(_ requestID: UUID) { if state.navigation?.id == requestID { change { $0.navigation = nil } } }
}
