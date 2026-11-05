import AppKit
import Foundation

@main struct ModelChecks {
  @MainActor static func wait(_ description: String, _ ready: () -> Bool) async {
    for _ in 0..<300 {
      if ready() { return }
      try? await Task.sleep(for: .milliseconds(20))
    }
    fatalError("Timed out: " + description)
  }
  @MainActor static func main() async {
    let destination = PasteDestination(processIdentifier: 42)
    precondition(
      destination.permitsPaste(
        frontmostProcessIdentifier: 42, targetTerminated: false, clipboard: "→", expected: "→"))
    precondition(
      !destination.permitsPaste(
        frontmostProcessIdentifier: 99, targetTerminated: false, clipboard: "→", expected: "→"))
    precondition(
      !destination.permitsPaste(
        frontmostProcessIdentifier: nil, targetTerminated: false, clipboard: "→", expected: "→"))
    precondition(
      !destination.permitsPaste(
        frontmostProcessIdentifier: 42, targetTerminated: true, clipboard: "→", expected: "→"))
    precondition(
      !destination.permitsPaste(
        frontmostProcessIdentifier: 42, targetTerminated: false, clipboard: "changed", expected: "→"
      ))
    let model = PickerModel()
    model.query = "arrow"
    await wait("synthetic results") { model.glyphs.count > 2 }
    let a = model.glyphs[0]
    let b = model.glyphs[1]
    model.inspect(a)
    model.selected = b.id
    try? await Task.sleep(for: .milliseconds(250))
    precondition(model.detail == nil, "A stale detail response survived selection B")
    var pasted: String?
    model.paste = { symbol, _ in pasted = symbol }
    model.pick()
    await wait("pick B") { pasted != nil }
    precondition(pasted == b.symbol, "Return picked stale A instead of highlighted B")
    model.inspect(a)
    model.inspect(b)
    await wait("latest detail") { model.detail?.record.id == b.id }
    precondition(model.detail?.record.id == b.id)
    model.inspect(a)
    model.query = "U+2190"
    await wait("new query result") { model.glyphs.first?.hexseq == "2190" }
    precondition(model.detail == nil, "Old details survived a changed query")
    let phone = PhoneUpdateService()
    phone.check(manual: true)
    phone.check(manual: true)
    await wait("serial phone cycle") { phone.operation == .idle }
    precondition(phone.message == "Synthetic phone consent is off.")
    precondition(phone.renewalMessage.contains("Signing remains valid"))
    let callsURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["UNIMAGIC_LIBRARY"]!)
      .appendingPathComponent("calls.jsonl")
    let first = try! String(contentsOf: callsURL, encoding: .utf8).split(separator: "\n").map {
      try! JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
    }
    precondition(
      first.count == 2 && first[0]["command"] as? String == "renew"
        && first[1]["command"] as? String == "check-updates")
    precondition(first[0]["forced"] as? Bool == false && first[1]["manual"] as? Bool == true)
    phone.check(manual: true)
    await wait("second phone check") { phone.operation == .idle }
    let later = try! String(contentsOf: callsURL, encoding: .utf8).split(separator: "\n")
    precondition(later.count == 3, "Healthy renewal repeated before its six-hour cadence")
    print(
      "Native model checks passed: changed/nil/terminated paste targets, changed clipboard, delayed detail A→B, Return chooses B, latest inspection wins, query invalidates details."
    )
  }
}
