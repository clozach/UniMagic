import AppKit

/// Synthetic capture harness is isolated from the production host lifecycle.
@MainActor func configureFixtureCapture(window: NSWindow, model: PickerModel) {
  let environment = ProcessInfo.processInfo.environment
  guard environment["UNIMAGIC_FIXTURE"] == "1", let path = environment["UNIMAGIC_CAPTURE"] else {
    return
  }
  if environment["UNIMAGIC_CAPTURE_SETTINGS"] == "1" { model.showingSettings = true }
  if let query = environment["UNIMAGIC_CAPTURE_QUERY"] { model.query = query }
  if let appearance = environment["UNIMAGIC_APPEARANCE"] {
    NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
  }
  DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
    if environment["UNIMAGIC_CAPTURE_DETAIL"] == "1" {
      model.inspect()
      DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        captureFixture(window: window, path: path)
      }
    } else {
      captureFixture(window: window, path: path)
    }
  }
}
@MainActor private func captureFixture(window: NSWindow, path: String) {
  guard let view = (NSApp.keyWindow ?? window).contentView,
    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
  else { Darwin.exit(1) }
  view.cacheDisplay(in: view.bounds, to: bitmap)
  do {
    guard let data = bitmap.representation(using: .png, properties: [:]) else { Darwin.exit(1) }
    try data.write(to: URL(fileURLWithPath: path))
    Darwin.exit(0)
  } catch {
    FileHandle.standardError.write(Data("Fixture capture could not be saved.\n".utf8))
    Darwin.exit(1)
  }
}
