import Foundation
import CryptoKit

struct SigningProfile {
    let path: String
    let uuid: String
    let app: String
    let expires: Date
    let devices: [String]
    let teams: [String]
    let certificates: [Data]
    let applicationGroups: [String]
    let usesAPNs: Bool
    init?(path: String, dictionary: [String: Any]) {
        guard let uuid = dictionary["UUID"] as? String,
              let entitlements = dictionary["Entitlements"] as? [String: Any],
              let app = entitlements["application-identifier"] as? String,
              let expires = dictionary["ExpirationDate"] as? Date,
              let devices = dictionary["ProvisionedDevices"] as? [String],
              let teams = dictionary["TeamIdentifier"] as? [String],
              let certificates = dictionary["DeveloperCertificates"] as? [Data] else { return nil }
        self.path = path; self.uuid = uuid; self.app = app; self.expires = expires
        self.devices = devices; self.teams = teams; self.certificates = certificates
        self.applicationGroups = entitlements["com.apple.security.application-groups"] as? [String] ?? []
        self.usesAPNs = entitlements["aps-environment"] != nil
    }
    func eligible(app: String, team: String, device: String, identity: String, now: Date, requiredGroups: [String] = []) -> Bool {
        self.app == team + "." + app && teams.contains(team) && devices.contains(device) && expires > now &&
        !usesAPNs && requiredGroups.allSatisfy(applicationGroups.contains) &&
        certificates.contains { Insecure.SHA1.hash(data: $0).map { String(format: "%02X", $0) }.joined() == identity }
    }
}
func newestSigningProfile(_ profiles: [SigningProfile], app: String, team: String, device: String, identity: String, now: Date, requiredGroups: [String] = []) -> SigningProfile? {
    profiles.filter { $0.eligible(app: app, team: team, device: device, identity: identity, now: now, requiredGroups: requiredGroups) }
        .sorted { $0.expires == $1.expires ? $0.uuid < $1.uuid : $0.expires > $1.expires }.first
}
func decodeSigningProfile(_ url: URL) -> SigningProfile? {
    let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    task.arguments = ["cms", "-D", "-i", url.path]
    let output = Pipe(); task.standardOutput = output; task.standardError = FileHandle.nullDevice
    do {
        try task.run()
        let data = output.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
        guard task.terminationStatus == 0,
              let dictionary = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return SigningProfile(path: url.path, dictionary: dictionary)
    } catch { return nil }
}
