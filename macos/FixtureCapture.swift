import AppKit

@MainActor func captureSettingsFixture(_ window: NSWindow) {
  let environment = ProcessInfo.processInfo.environment
  guard environment["UNIMAGIC_FIXTURE"] == "1", let path = environment["UNIMAGIC_CAPTURE"] else { return }
  if let appearance = environment["UNIMAGIC_APPEARANCE"] {
    NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
  }
  DispatchQueue.main.asyncAfter(deadline: .now() + 3) { captureFixture(window: window, path: path) }
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
