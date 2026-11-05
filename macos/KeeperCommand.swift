import Foundation

enum KeeperCommandResult: Sendable {
  case succeeded(String)
  case failed(String)
  var message: String {
    switch self {
    case .succeeded(let message), .failed(let message): return message
    }
  }
  var succeeded: Bool {
    if case .succeeded = self { return true }
    return false
  }
}
/// The keeper owns consent, authentication, frozen-content renewal and its cross-process lock.
func executeKeeper(
  executable: URL, script: URL, arguments: [String], renewal: Bool, environment: [String: String]
) async -> KeeperCommandResult {
  let process = Process()
  let output = Pipe()
  let errors = Pipe()
  process.executableURL = executable
  process.arguments = [script.path] + arguments
  process.environment = environment
  process.standardOutput = output
  process.standardError = errors
  do {
    try process.run()
    let stderr = Task.detached { errors.fileHandleForReading.readDataToEndOfFile() }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let errorData = await stderr.value
    let resultData = data.isEmpty ? errorData : data
    guard let object = try JSONSerialization.jsonObject(with: resultData) as? [String: Any] else {
      return .failed(
        "The paired-phone helper returned an unreadable result. Check the phone is paired and try again."
      )
    }
    if let error = object["error"] as? String { return .failed(String(error.prefix(500))) }
    if renewal {
      if object["kind"] as? String == "healthy", let expiry = object["expiresAt"] as? Double {
        let date = Date(timeIntervalSince1970: expiry / 1000)
        return .succeeded(
          "Signing remains valid through " + date.formatted(date: .abbreviated, time: .omitted)
            + ". Frozen-content renewal is separate from feature updates.")
      }
      if let release = object["release"] as? [String: Any],
        let expiry = release["expiresAt"] as? Double
      {
        return .succeeded(
          "The registered frozen iPhone release was renewed through "
            + Date(timeIntervalSince1970: expiry / 1000).formatted(
              date: .abbreviated, time: .omitted) + ".")
      }
      return .failed(
        "Signing renewal could not be verified. Check the paired-phone installation and try again.")
    }
    guard let kind = object["kind"] as? String,
      ["off", "waiting", "current", "available", "installed", "error"].contains(kind),
      let message = object["message"] as? String
    else {
      return .failed(
        "The iPhone update check returned an unreadable result. Check pairing and try again.")
    }
    return kind == "error" ? .failed(message) : .succeeded(message)
  } catch {
    return .failed(
      "The paired-phone helper could not run. Reopen the complete UniMagic app and check the paired phone."
    )
  }
}
