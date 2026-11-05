import Foundation

@main
struct SourceGraphTests {
    static func main() throws {
        let fm = FileManager.default
        let temporary = fm.temporaryDirectory.appendingPathComponent("release-source-graph-" + UUID().uuidString)
        defer { try? fm.removeItem(at: temporary) }
        let source = temporary.appendingPathComponent("source")
        let seeds = temporary.appendingPathComponent("seeds")
        let frozen = temporary.appendingPathComponent("frozen")
        for folder in [source, seeds, frozen] { try fm.createDirectory(at: folder, withIntermediateDirectories: true) }
        func write(_ text: String, _ path: URL) throws {
            try fm.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: path)
        }
        try write("{}", source.appendingPathComponent("release-product.json"))
        try write("original source", source.appendingPathComponent("App.swift"))
        // Excluded REGULAR entries must not make DirectoryEnumerator skip a
        // later required directory; exercise native enumerator ordering.
        for index in 0..<40 {
            try write("derived",source.appendingPathComponent("skip-\(index).js"))
            try write("required",source.appendingPathComponent("required-\(index)/input.txt"))
        }
        try write("preserved keyword", seeds.appendingPathComponent("words.json"))
        try write("private fixture", seeds.appendingPathComponent("private.json"))
        try write("preserved category", temporary.appendingPathComponent("research/inventory.json"))
        try fm.createSymbolicLink(at: source.appendingPathComponent("node_modules"), withDestinationURL: temporary.appendingPathComponent("missing-package"))
        var product = PublisherProduct.current
        product.name = "UniMagic"
        product.identityAlgorithm = "unimagic-content-v1"
        product.identityExact = ["release-product.json"]
        product.identityPrefixes = ["seeds/", "reference/"]
        product.excludePrefixes = ["node_modules", "macos/build", "seeds/private.json"] + (0..<40).map { "skip-\($0).js" }
        product.sourceMappings = ["seeds": "../seeds", "reference/inventory.json": "../research/inventory.json"]
        PublisherProduct.current = product
        let effective = try ContentIdentity.files(at: source)
        precondition((0..<40).allSatisfy { effective["required-\($0)/input.txt"] != nil }, "Excluded files never skip required sibling directories")
        precondition(effective["seeds/private.json"] == nil, "Exclusions also cover mapped graph")
        precondition(effective["node_modules"] == nil, "Exclude symlink before resolving it")
        precondition(effective["seeds/words.json"]?.lastPathComponent == "words.json", "Virtual seed path points at original")
        precondition(effective["reference/inventory.json"] != nil, "Virtual leaf mapping is included")
        for (relative, original) in effective {
            let destination = frozen.appendingPathComponent(relative)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: original, to: destination)
        }
        let originalFingerprint = try ContentIdentity.local(source)
        let frozenFingerprint = try ContentIdentity.local(frozen)
        precondition(originalFingerprint == frozenFingerprint, "Canonical graph and frozen export have identical fingerprint")
        try write("frozen override", frozen.appendingPathComponent("seeds/words.json"))
        let alteredFingerprint = try ContentIdentity.local(frozen)
        precondition(originalFingerprint != alteredFingerprint, "Frozen real path wins over canonical fallback")
        try fm.createSymbolicLink(at: seeds.appendingPathComponent("leak"), withDestinationURL: source.appendingPathComponent("App.swift"))
        do { _ = try ContentIdentity.files(at: source); fatalError("Mapping must refuse symlinks") }
        catch IdentityError.symlink { }
        print("Shared source graph tests passed: 8 assertions")
    }
}
