import Foundation
import zlib

/// Strict ZIP32 preflight. Metadata, file kinds, geometry and actual inflated
/// sizes/CRC are checked before ditto is allowed to write a single archive entry.
enum UpdateArchiveValidation {
    struct Limits {
        var entries = 20_000
        var file = 250 * 1_024 * 1_024
        var total = 750 * 1_024 * 1_024
    }
    private struct Entry {
        let start: Int, end: Int, data: Int, compressed: Int, expanded: Int, method: Int
        let crc: UInt32
    }

    static func validate(_ bytes: Data, bundleName: String, limits: Limits = Limits()) throws {
        func fail(_ text: String = "the download is not a readable archive") throws -> Never { throw UpdateFailure.unsafeArchive(text) }
        func integer(_ at: Int, _ width: Int) throws -> Int {
            guard at >= 0, width <= bytes.count, at <= bytes.count - width else { try fail() }
            return (0..<width).reduce(0) { $0 | Int(bytes[at + $1]) << (8 * $1) }
        }
        func extra(_ start: Int, _ size: Int) throws {
            var cursor = start
            while cursor < start + size {
                guard cursor + 4 <= start + size else { try fail() }
                let kind = try integer(cursor, 2), length = try integer(cursor + 2, 2)
                // ZIP64 and alternate Unicode path metadata can change what an
                // extractor sees; accept only the one agreed UTF-8 name.
                guard ![1, 0x7075, 0x756e, 0x000d].contains(kind), cursor + 4 + length <= start + size else { try fail("unsupported ZIP metadata") }
                cursor += 4 + length
            }
        }
        guard bytes.count >= 22 else { try fail() }
        var end: Int?
        for position in stride(from: bytes.count - 22, through: max(0, bytes.count - 65_557), by: -1) {
            if try integer(position, 4) == 0x06054b50, position + 22 + (try integer(position + 20, 2)) == bytes.count { end = position; break }
        }
        guard let end else { try fail() }
        let count = try integer(end + 10, 2), centralSize = try integer(end + 12, 4), central = try integer(end + 16, 4)
        guard try integer(end + 4, 2) == 0, try integer(end + 6, 2) == 0, try integer(end + 8, 2) == count,
              count > 0, count < 65_535, count <= limits.entries, centralSize < 0xffff_ffff,
              central < 0xffff_ffff, central + centralSize == end else { try fail("unsupported or oversized ZIP directory") }
        var cursor = central, total = 0, names = Set<String>(), entries: [Entry] = []
        for _ in 0..<count {
            guard cursor + 46 <= end, try integer(cursor, 4) == 0x02014b50 else { try fail() }
            let flags = try integer(cursor + 8, 2), method = try integer(cursor + 10, 2), crc = try integer(cursor + 16, 4)
            let compressed = try integer(cursor + 20, 4), expanded = try integer(cursor + 24, 4)
            let length = try integer(cursor + 28, 2), extraSize = try integer(cursor + 30, 2), comment = try integer(cursor + 32, 2)
            let mode = try (integer(cursor + 38, 4) >> 16) & 0xf000, local = try integer(cursor + 42, 4)
            guard try (10...20).contains(integer(cursor + 6, 2)),
                  cursor + 46 + length + extraSize + comment <= end, flags & ~0x080e == 0,
                  method == 0 || method == 8, compressed < 0xffff_ffff, expanded < 0xffff_ffff,
                  local < 0xffff_ffff, try integer(cursor + 34, 2) == 0,
                  expanded <= limits.file, expanded <= limits.total - total else { try fail("unsupported or oversized ZIP entry") }
            total += expanded
            let nameBytes = bytes.subdata(in: cursor + 46..<cursor + 46 + length)
            guard let name = String(data: nameBytes, encoding: .utf8), !name.isEmpty, nameBytes.count <= 1_024,
                  !name.contains("\0"), !name.contains(":"), !name.contains("\n"), !name.contains("\r"),
                  name.split(separator: "/").allSatisfy({ !$0.isEmpty && $0 != "." && $0.utf8.count <= 255 }),
                  name == name.precomposedStringWithCanonicalMapping else { try fail("unsupported ZIP path") }
            if let bad = UpdateArchive.unsafeEntry(in: [name], bundleName: bundleName) { try fail(bad) }
            guard !name.contains("//"), mode == 0 || mode == 0x8000 || mode == 0x4000,
                  mode != 0x4000 || name.hasSuffix("/"), !name.hasSuffix("/") || expanded == 0,
                  !names.contains(name.lowercased()) else { try fail("unsafe or duplicate ZIP entry") }
            names.insert(name.lowercased())
            guard local + 30 <= central, try integer(local, 4) == 0x04034b50 else { try fail() }
            let localLength = try integer(local + 26, 2), localExtra = try integer(local + 28, 2)
            let data = local + 30 + localLength + localExtra, payloadEnd = data + compressed
            guard data <= central, payloadEnd <= central,
                  try integer(local + 4, 2) == integer(cursor + 6, 2),
                  try integer(local + 6, 2) == flags, try integer(local + 8, 2) == method,
                  bytes.subdata(in: local + 30..<local + 30 + localLength) == nameBytes else { try fail("ZIP local and central entries disagree") }
            try extra(cursor + 46 + length, extraSize)
            try extra(local + 30 + localLength, localExtra)
            var rangeEnd = payloadEnd
            if flags & 8 == 0 {
                guard try integer(local + 14, 4) == crc, try integer(local + 18, 4) == compressed,
                      try integer(local + 22, 4) == expanded else { try fail("ZIP local and central sizes disagree") }
            } else {
                guard try [0, crc].contains(integer(local + 14, 4)), try [0, compressed].contains(integer(local + 18, 4)),
                      try [0, expanded].contains(integer(local + 22, 4)) else { try fail("ZIP descriptor header disagrees") }
                let descriptor = try integer(payloadEnd, 4) == 0x08074b50 ? payloadEnd + 4 : payloadEnd
                guard descriptor + 12 <= central, try integer(descriptor, 4) == crc,
                      try integer(descriptor + 4, 4) == compressed, try integer(descriptor + 8, 4) == expanded else { try fail("invalid ZIP data descriptor") }
                rangeEnd = descriptor + 12
            }
            entries.append(Entry(start: local, end: rangeEnd, data: data, compressed: compressed, expanded: expanded, method: method, crc: UInt32(crc)))
            cursor += 46 + length + extraSize + comment
        }
        guard cursor == end else { try fail() }
        let ordered = entries.sorted { $0.start < $1.start }
        guard ordered.first?.start == 0 else { try fail("unexpected ZIP prefix") }
        for (index, entry) in ordered.enumerated() {
            guard entry.end == (index + 1 < ordered.count ? ordered[index + 1].start : central) else { try fail("overlapping or unaccounted ZIP data") }
            try validatePayload(bytes, entry)
        }
    }

    private static func validatePayload(_ bytes: Data, _ entry: Entry) throws {
        func fail() throws -> Never { throw UpdateFailure.unsafeArchive("ZIP payload does not match its declared size and checksum") }
        var checksum: uLong = crc32(0, nil, 0)
        if entry.method == 0 {
            guard entry.compressed == entry.expanded else { try fail() }
            checksum = bytes.withUnsafeBytes { raw in crc32(checksum, raw.bindMemory(to: Bytef.self).baseAddress!.advanced(by: entry.data), uInt(entry.compressed)) }
        } else {
            var stream = z_stream()
            guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { try fail() }
            defer { inflateEnd(&stream) }
            var output = [UInt8](repeating: 0, count: 65_536)
            var produced = 0
            try bytes.withUnsafeBytes { raw in
                stream.next_in = UnsafeMutablePointer(mutating: raw.bindMemory(to: Bytef.self).baseAddress!.advanced(by: entry.data))
                stream.avail_in = uInt(entry.compressed)
                while true {
                    let status = output.withUnsafeMutableBytes { buffer -> Int32 in
                        stream.next_out = buffer.bindMemory(to: Bytef.self).baseAddress!
                        stream.avail_out = uInt(buffer.count)
                        return inflate(&stream, Z_NO_FLUSH)
                    }
                    let amount = output.count - Int(stream.avail_out)
                    guard amount <= entry.expanded - produced else { try fail() }
                    produced += amount
                    checksum = output.withUnsafeBytes { crc32(checksum, $0.bindMemory(to: Bytef.self).baseAddress!, uInt(amount)) }
                    if status == Z_STREAM_END { break }
                    guard status == Z_OK, amount > 0 || stream.avail_in > 0 else { try fail() }
                }
                guard produced == entry.expanded, stream.avail_in == 0 else { try fail() }
            }
        }
        guard UInt32(truncatingIfNeeded: checksum) == entry.crc else { try fail() }
    }
}
