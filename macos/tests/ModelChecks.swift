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
    let initialChanges = NSPasteboard.general.changeCount
    let destination = DesktopPaste()
    destination.begin()
    destination.perform(text: "👋", keepOpen: false, observedPID: nil) { _ in check(false) }
    destination.perform(text: "𒅲", keepOpen: true, observedPID: nil) { _ in check(false) }
    let board = NSPasteboard(name: .init("UniMagic-fixture-\(ProcessInfo.processInfo.processIdentifier)"))
    check(board.string(forType: .string) == "𒅲" && NSPasteboard.general.changeCount == initialChanges,
          "The isolated fixture must keep both paste modes off the system clipboard")
    let model = SettingsModel()
    await model.refreshCategories()
    check(!model.categories.isEmpty, "Desktop categories did not load")
    guard let category = model.categories.first(where: { $0.id == "set:Emojis" }) else { Darwin.exit(1) }
    model.toggle(category)
    await wait("category write") { model.categories.first(where: { $0.id == category.id })?.enabled == !category.enabled }
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
    await model.refreshCategories()
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
      "Native settings checks passed: category visibility, external store refresh, serialized phone checks and renewal cadence."
    )
  }
}
