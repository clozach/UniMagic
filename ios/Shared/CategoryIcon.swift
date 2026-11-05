import SwiftUI

/// Legacy exemplar IDs remain decodable; their artwork is supplied by the OS.
/// No copied font software is loaded or shipped. User Unicode/emoji overrides
/// bypass this adapter and retain the normal fallback labels.
enum CategoryIcon {
    private static let symbols: [String: String] = {
        guard let url = Bundle.main.url(forResource: "CategoryArtwork", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(Artwork.self, from: data), document.schemaVersion == 1 else { return [:] }
        return document.symbols
    }()
    private struct Artwork: Decodable { let schemaVersion: Int; let symbols: [String: String] }
    static func systemName(for legacySymbol: String) -> String {
        guard let scalar = legacySymbol.unicodeScalars.first else { return "square.grid.3x3" }
        return symbols[String(scalar.value, radix: 16).uppercased()] ?? "square.grid.3x3"
    }
}
