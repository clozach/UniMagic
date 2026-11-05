import AppKit
import SwiftUI

@MainActor final class PickerModel: ObservableObject {
  let release = ReleaseSettings()
  let phoneUpdates = PhoneUpdateService()
  @Published var query = "" { didSet { reload() } }
  @Published var category = "recents" { didSet { reload() } }
  @Published var categories: [Category] = []
  @Published var glyphs: [Glyph] = []
  @Published var selected: String? {
    didSet {
      if selected != oldValue {
        detail = nil
        detailGeneration += 1
      }
    }
  }
  @Published var detail: GlyphDetail?
  @Published var message = "Loading desktop library…"
  @Published var keepOpen = false
  @Published var showingSettings = false
  @Published var term = ""
  private var bridge: DesktopBridge?
  private var generation = 0
  private var detailGeneration = 0
  private var nextOffset: Int?, historyCursor: String?
  var dismiss: (() -> Void)?
  var paste: ((String, Bool) -> Void)?
  var canLoadMore: Bool { nextOffset != nil || historyCursor != nil }
  var current: Glyph? { glyphs.first { $0.id == selected } ?? glyphs.first }
  init() {
    do {
      bridge = try DesktopBridge()
      Task {
        await refreshCategories()
        reload()
      }
    } catch { message = error.localizedDescription }
  }
  func refreshCategories() async {
    do { categories = try await bridge!.request("categories", as: [Category].self) } catch {
      message = error.localizedDescription
    }
  }
  func reload() {
    guard let bridge else { return }
    detail = nil
    detailGeneration += 1
    generation += 1
    let ticket = generation
    Task {
      do {
        let page = try await bridge.request(
          "list", ["query": query, "category": category], as: GlyphPage.self)
        guard ticket == generation else { return }
        glyphs = page.records
        selected = glyphs.first?.id
        nextOffset = page.nextOffset
        historyCursor = page.cursor
        message = "\(page.total) " + (page.total == 1 ? "glyph" : "glyphs")
        detail = nil
      } catch { message = error.localizedDescription }
    }
  }
  func more() {
    guard let bridge, nextOffset != nil || historyCursor != nil else { return }
    let ticket = generation
    var args: [String: Any] = ["query": query, "category": category]
    if let offset = nextOffset { args["offset"] = offset }
    if let cursor = historyCursor { args["cursor"] = cursor }
    nextOffset = nil
    historyCursor = nil
    Task {
      do {
        let page = try await bridge.request("list", args, as: GlyphPage.self)
        guard ticket == generation else { return }
        glyphs += page.records
        nextOffset = page.nextOffset
        historyCursor = page.cursor
      } catch { message = error.localizedDescription }
    }
  }
  func inspect(_ glyph: Glyph? = nil) {
    guard let glyph = glyph ?? current, let bridge else { return }
    selected = glyph.id
    detailGeneration += 1
    let ticket = detailGeneration
    Task {
      do {
        let loaded = try await bridge.request("details", ["id": glyph.id], as: GlyphDetail.self)
        guard ticket == detailGeneration, selected == glyph.id else { return }
        detail = loaded
      } catch { message = error.localizedDescription }
    }
  }
  func pick(
    _ glyph: Glyph? = nil, symbol: String? = nil, copy: Bool = false, opposite: Bool = false
  ) {
    guard let glyph = glyph ?? (detail?.record.id == selected ? detail?.record : nil) ?? current,
      let bridge
    else { return }
    let text = symbol ?? glyph.symbol
    let stays = opposite ? !keepOpen : keepOpen
    Task {
      do {
        let _: Bool = try await bridge.request(
          "pick",
          ["id": glyph.id, "symbol": text, "query": query, "action": copy ? "copy" : "insert"],
          as: Bool.self)
        if copy {
          Self.copy(text)
          message = "Copied \(text)"
          if !stays { dismiss?() }
        } else {
          paste?(text, stays)
        }
      } catch { message = error.localizedDescription }
    }
  }
  static func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }
  func learn(_ operation: String, term: String) {
    guard let glyph = detail?.record, !term.trimmingCharacters(in: .whitespaces).isEmpty, let bridge
    else { return }
    Task {
      do {
        let _: Bool = try await bridge.request(
          operation, ["id": glyph.id, "term": term], as: Bool.self)
        self.term = ""
        inspect(glyph)
      } catch { message = error.localizedDescription }
    }
  }
  func toggle(_ category: Category) {
    guard let bridge else { return }
    Task {
      do {
        let _: Bool = try await bridge.request(
          "visibility", ["category": category.id, "enabled": !category.enabled], as: Bool.self)
        await refreshCategories()
      } catch { message = error.localizedDescription }
    }
  }
  func setIcon(_ category: Category, symbol: String?) {
    guard let bridge else { return }
    var arguments: [String: Any] = ["category": category.id]
    arguments["symbol"] = symbol ?? NSNull() as Any
    Task {
      do {
        let _: Bool = try await bridge.request("exemplar", arguments, as: Bool.self)
        await refreshCategories()
      } catch { message = error.localizedDescription }
    }
  }
  func move(_ delta: Int) {
    guard !glyphs.isEmpty else { return }
    let position = glyphs.firstIndex(where: { $0.id == selected }) ?? 0
    selected = glyphs[min(max(position + delta, 0), glyphs.count - 1)].id
  }
}
