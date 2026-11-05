import Foundation
import CryptoKit
let now = Date(timeIntervalSince1970: 1000)
let certificate = Data("fixture certificate".utf8)
let identity = Insecure.SHA1.hash(data: certificate).map { String(format: "%02X", $0) }.joined()
func profile(_ uuid: String, seconds: Double, app: String = "T.app", device: String = "phone", team: String = "T", cert: Data = certificate, groups: [String] = [], apns: Bool = false) -> SigningProfile {
    var entitlements: [String: Any] = ["application-identifier": app, "com.apple.security.application-groups": groups]
    if apns { entitlements["aps-environment"] = "development" }
    return SigningProfile(path: "/fixture/" + uuid, dictionary: ["UUID": uuid, "ExpirationDate": now.addingTimeInterval(seconds), "Entitlements": entitlements, "ProvisionedDevices": [device], "TeamIdentifier": [team], "DeveloperCertificates": [cert]])!
}
func select(_ values: [SigningProfile]) -> String? {
    newestSigningProfile(values, app: "app", team: "T", device: "phone", identity: identity, now: now)?.uuid
}
precondition(select([profile("old", seconds: 10), profile("fresh", seconds: 100)]) == "fresh")
precondition(select([profile("expired", seconds: -1)]) == nil)
precondition(select([profile("wrong-app", seconds: 100, app: "T.other")]) == nil)
precondition(select([profile("wrong-team", seconds: 100, team: "other")]) == nil)
precondition(select([profile("wrong-device", seconds: 100, device: "other")]) == nil)
precondition(select([profile("wrong-cert", seconds: 100, cert: Data("other".utf8))]) == nil)
precondition(select([profile("z", seconds: 100), profile("a", seconds: 100)]) == "a")
precondition(SigningProfile(path: "malformed", dictionary: [:]) == nil)
let group = "group.com.clozach.amaanah.unimagic"
let candidateProfiles = [profile("isolated-newer", seconds: 200), profile("shared", seconds: 100, groups: [group])]
precondition(newestSigningProfile(candidateProfiles, app: "app", team: "T", device: "phone", identity: identity, now: now, requiredGroups: [group])?.uuid == "shared")
precondition(newestSigningProfile([candidateProfiles[0]], app: "app", team: "T", device: "phone", identity: identity, now: now, requiredGroups: [group]) == nil)
precondition(select([profile("paid", seconds: 100, apns: true)]) == nil)
print("11 signing-profile selection checks passed")
