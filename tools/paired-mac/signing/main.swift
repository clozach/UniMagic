import Foundation
guard CommandLine.arguments.count > 1, !CommandLine.arguments[1].hasPrefix("--") else {
    FileHandle.standardError.write(Data("Usage: select-profiles <cache-directory> [--device ID --team TEAM --bundle ID --identity SHA1 --keyboard --app-group GROUP].\n".utf8)); exit(64)
}
func option(_ name: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: name), CommandLine.arguments.indices.contains(index + 1) else { return nil }
    return CommandLine.arguments[index + 1]
}
struct NativeDevice: Decodable { let identifier: String }
let privateDeviceFile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("amaanah/iphone-agent-alerts/native-device.json")
let savedDevice = (try? Data(contentsOf: privateDeviceFile)).flatMap { try? JSONDecoder().decode(NativeDevice.self, from: $0).identifier }
guard let device = option("--device") ?? ProcessInfo.processInfo.environment["UNIMAGIC_DEVICE_ID"] ?? savedDevice,
      device.range(of: "^[A-Fa-f0-9-]{16,80}$", options: .regularExpression) != nil else {
    FileHandle.standardError.write(Data("Paired device unconfigured; supply --device or private native-device.json.\n".utf8)); exit(64)
}
let team = option("--team") ?? "AD29JN9GKN"
let bundle = option("--bundle") ?? "com.clozach.amaanah.alerts"
let identity = option("--identity") ?? "8570B3D50CF453628EF2656136D36C7E47D47569"
let groupFlag = CommandLine.arguments.firstIndex(of: "--app-group")
var requiredGroups: [String] = []
if let groupFlag {
    guard CommandLine.arguments.indices.contains(groupFlag + 1),
          CommandLine.arguments[groupFlag + 1].range(of: "^group\\.[A-Za-z0-9.-]+$", options: .regularExpression) != nil,
          CommandLine.arguments.contains("--keyboard") else {
        FileHandle.standardError.write(Data("Unsupported App Group or missing keyboard.\n".utf8)); exit(64)
    }
    requiredGroups = [CommandLine.arguments[groupFlag + 1]]
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let profiles = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "mobileprovision" }.compactMap(decodeSigningProfile)
let now = Date(); var result: [String: String] = [:]
let targets = ["app", "service"] + (CommandLine.arguments.contains("--keyboard") ? ["keyboard"] : [])
for key in targets {
    let app = bundle + (key == "app" ? "" : "." + key)
    guard let profile = newestSigningProfile(profiles, app: app, team: team, device: device, identity: identity, now: now, requiredGroups: key == "service" ? [] : requiredGroups) else {
        FileHandle.standardError.write(Data("No valid matching profile for \(app).\n".utf8)); exit(1)
    }
    result[key + "_path"] = profile.path; result[key + "_uuid"] = profile.uuid
    result[key + "_expires"] = ISO8601DateFormatter().string(from: profile.expires)
}
print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), encoding: .utf8)!)
