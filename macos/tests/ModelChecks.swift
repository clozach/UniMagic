import AppKit
import Foundation

@main struct ModelChecks {
  @MainActor static var diagnostics: () -> String = { "before model initialization" }
  @MainActor static func check(
    _ condition: @autoclosure () -> Bool, _ message: String = "assertion",
    file: StaticString = #fileID, line: UInt = #line
  ) {
    guard condition() else {
      FileHandle.standardError.write(
        Data("ModelChecks failed at \(file):\(line): \(message); \(diagnostics())\n".utf8))
      Darwin.exit(1)
    }
  }

  @MainActor static func wait(_ description: String, _ ready: () -> Bool) async {
    for _ in 0..<300 {
      if ready() { return }
      try? await Task.sleep(for: .milliseconds(20))
    }
    check(false, "Timed out: " + description)
  }
  @MainActor static func main() async {
    let destination = PasteDestination(processIdentifier: 42)
    check(
      destination.permitsPaste(
        frontmostProcessIdentifier: 42, targetTerminated: false, clipboard: "→", expected: "→"))
    check(
      !destination.permitsPaste(
        frontmostProcessIdentifier: 99, targetTerminated: false, clipboard: "→", expected: "→"))
    check(
      !destination.permitsPaste(
        frontmostProcessIdentifier: nil, targetTerminated: false, clipboard: "→", expected: "→"))
    check(
      !destination.permitsPaste(
        frontmostProcessIdentifier: 42, targetTerminated: true, clipboard: "→", expected: "→"))
    check(
      !destination.permitsPaste(
        frontmostProcessIdentifier: 42, targetTerminated: false, clipboard: "changed", expected: "→"
      ))
    let model = PickerModel()
    diagnostics = {
      "query=\(model.query), selected=\(model.selected ?? "nil"), detail=\(model.detail?.record.id ?? "nil"), first=\(model.glyphs.first?.id ?? "nil"), count=\(model.glyphs.count), message=\(model.message)"
    }
    model.query = "arrow"
    await wait("synthetic results") { model.glyphs.count > 2 }
    let a = model.glyphs[0]
    let b = model.glyphs[1]
    model.inspect(a)
    model.selected = b.id
    try? await Task.sleep(for: .milliseconds(250))
    check(model.detail == nil, "A stale detail response survived selection B")
    var pasted: String?
    model.paste = { symbol, _ in pasted = symbol }
    model.pick()
    await wait("pick B") { pasted != nil }
    check(pasted == b.symbol, "Return picked stale A instead of highlighted B")
    model.inspect(a)
    model.inspect(b)
    await wait("latest detail") { model.detail?.record.id == b.id }
    check(model.detail?.record.id == b.id)
    model.selected = a.id
    let pendingRefresh = Task { await model.refreshForPresentation() }
    await Task.yield()
    model.selected = b.id
    await pendingRefresh.value
    try? await Task.sleep(for: .milliseconds(250))
    check(model.selected == b.id, "Late presentation refresh reset the newer selection")
    await model.refreshForPresentation()
    try? await Task.sleep(for: .milliseconds(250))
    check(model.selected == b.id, "An unchanged presentation refresh lost selection B")
    model.inspect(a)
    model.query = "U+2190"
    await wait("new query result") { model.glyphs.first?.hexseq == "2190" }
    check(model.detail == nil, "Old details survived a changed query")
    let preferencesURL = URL(
      fileURLWithPath: ProcessInfo.processInfo.environment["UNIMAGIC_LIBRARY"]!
    ).appendingPathComponent("personalization-v1.json")
    var preferences =
      try! JSONSerialization.jsonObject(with: Data(contentsOf: preferencesURL)) as! [String: Any]
    var browsePreferences = preferences["browsePreferences"] as! [String: Any]
    var visibility = browsePreferences["categoryVisibility"] as! [String: Any]
    visibility["set:Emojis"] = false
    browsePreferences["categoryVisibility"] = visibility
    preferences["browsePreferences"] = browsePreferences
    try! JSONSerialization.data(withJSONObject: preferences).write(
      to: preferencesURL, options: .atomic)
    await model.refreshForPresentation()
    check(
      model.categories.first(where: { $0.id == "set:Emojis" })?.enabled == false,
      "Fresh presentation did not read external category visibility")
    let phone = PhoneUpdateService()
    phone.check(manual: true)
    phone.check(manual: true)
    await wait("serial phone cycle") { phone.operation == .idle }
    check(phone.message == "Synthetic phone consent is off.")
    check(phone.renewalMessage.contains("Signing remains valid"))
    let callsURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["UNIMAGIC_LIBRARY"]!)
      .appendingPathComponent("calls.jsonl")
    let first = try! String(contentsOf: callsURL, encoding: .utf8).split(separator: "\n").map {
      try! JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
    }
    check(
      first.count == 2 && first[0]["command"] as? String == "renew"
        && first[1]["command"] as? String == "check-updates")
    check(first[0]["forced"] as? Bool == false && first[1]["manual"] as? Bool == true)
    phone.check(manual: true)
    await wait("second phone check") { phone.operation == .idle }
    let later = try! String(contentsOf: callsURL, encoding: .utf8).split(separator: "\n")
    check(later.count == 3, "Healthy renewal repeated before its six-hour cadence")
    print(
      "Native model checks passed: changed/nil/terminated paste targets, changed clipboard, delayed detail A→B, Return chooses B, latest inspection wins, query invalidates details."
    )
  }
}
