import Foundation

struct Glyph: Codable, Identifiable, Hashable {
  let id: String
  let hexseq: String
  let symbol: String
  let display: String
  let name: String
}
struct Category: Codable, Identifiable {
  let id: String
  let title: String
  let enabled: Bool
  let icon: String?
  let systemIcon: String?
}
struct GlyphPage: Codable {
  let records: [Glyph]
  let total: Int
  let nextOffset: Int?
  let cursor: String?
}
struct ValueRow: Codable, Identifiable {
  var id: String { label + value }
  let label: String
  let value: String
}
struct Alias: Codable, Identifiable {
  var id: String { term }
  let term: String
  let type: String
}
struct GlyphDetail: Codable {
  let record: Glyph
  let values: [ValueRow]
  let notes: [String]
  let components: [String]
  let classification: String
  let aliases: [Alias]
  let keywords: [String]
  let variants: [String]
  let twins: [Glyph]
  let related: [Glyph]
  let contexts: [Category]
}

/// One serial pipe preserves request ordering and isolates the desktop runtime from UI work.
final class DesktopBridge: @unchecked Sendable {
  private static let activityLock = NSLock()
  private static var requests = 0
  static var hasPendingRequests: Bool {
    activityLock.lock()
    defer { activityLock.unlock() }
    return requests > 0
  }
  private static func recordRequest(_ delta: Int) {
    activityLock.lock()
    requests += delta
    activityLock.unlock()
  }
  private let process = Process()
  private let input = Pipe(), output = Pipe(), errors = Pipe()
  private let queue = DispatchQueue(label: "UniMagic.desktop-engine")
  private var buffer = Data()
  init() throws {
    let resources = Bundle.main.resourceURL!
    process.executableURL = resources.appendingPathComponent("node")
    process.arguments = [resources.appendingPathComponent("bridge.cjs").path]
    process.standardInput = input
    process.standardOutput = output
    process.standardError = errors
    process.environment = ProcessInfo.processInfo.environment.filter {
      !$0.key.hasPrefix("NODE_") && !$0.key.hasPrefix("DYLD_")
    }
    try process.run()
  }
  deinit {
    try? input.fileHandleForWriting.close()
    process.terminate()
  }
  func request<T: Decodable>(_ operation: String, _ arguments: [String: Any] = [:], as type: T.Type)
    async throws -> T
  {
    Self.recordRequest(1)
    return try await withCheckedThrowingContinuation { continuation in
      queue.async { [self] in
        defer { Self.recordRequest(-1) }
        do {
          var request = arguments
          request["op"] = operation
          request["requestID"] = UUID().uuidString
          var bytes = try JSONSerialization.data(withJSONObject: request)
          bytes.append(10)
          try input.fileHandleForWriting.write(contentsOf: bytes)
          while !buffer.contains(10) {
            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else {
              throw NSError(
                domain: "UniMagic", code: 1,
                userInfo: [
                  NSLocalizedDescriptionKey:
                    "Desktop engine stopped. "
                    + (String(
                      data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
                      ?? "Reopen UniMagic; your library is preserved.")
                ])
            }
            buffer.append(chunk)
          }
          let end = buffer.firstIndex(of: 10)!
          let line = buffer.prefix(upTo: end)
          buffer.removeSubrange(...end)
          let envelope = try JSONSerialization.jsonObject(with: line) as! [String: Any]
          if let error = envelope["error"] as? String {
            throw NSError(domain: "UniMagic", code: 2, userInfo: [NSLocalizedDescriptionKey: error])
          }
          let value = try JSONSerialization.data(
            withJSONObject: envelope["result"]!, options: [.fragmentsAllowed])
          continuation.resume(returning: try JSONDecoder().decode(T.self, from: value))
        } catch { continuation.resume(throwing: error) }
      }
    }
  }
}
