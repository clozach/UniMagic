import SwiftUI

@MainActor final class SettingsModel: ObservableObject {
  let release = ReleaseSettings()
  let phoneUpdates = PhoneUpdateService()
  @Published var categories: [Category] = []
  @Published var message = ""
  private var bridge: DesktopBridge?

  func refreshCategories() async {
    do {
      if bridge == nil { bridge = try DesktopBridge() }
      guard let bridge else { return }
      categories = try await bridge.request("categories", as: [Category].self)
      message = ""
    } catch { message = error.localizedDescription }
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
}
