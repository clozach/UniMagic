import Foundation
import zlib

/// Synthetic ZIP records and a bounded URL protocol; no network or user data.
@main enum ArchiveSecurityTests {
    static var assertions = 0
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        precondition(condition(), name); assertions += 1
    }
    static func number(_ value: Int, _ width: Int) -> Data { Data((0..<width).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }) }
    static func set(_ data: inout Data, _ offset: Int, _ value: Int, _ width: Int = 4) { data.replaceSubrange(offset..<offset + width, with: number(value, width)) }
    static func crc(_ data: Data) -> Int { data.withUnsafeBytes { Int(crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(data.count))) } }
    static func zip(_ names: [String] = ["Test.app/file"], payload: Data = Data("hello".utf8), method: Int = 0,
                    expanded: Int? = nil, mode: Int = 0x8000, flags: Int = 0, extra: Data = Data()) -> Data {
        var locals = Data(), directory = Data()
        for name in names {
            let path = Data(name.utf8), offset = locals.count, count = expanded ?? payload.count, checksum = crc(payload)
            for (value, width) in [(0x04034b50,4),(20,2),(flags,2),(method,2),(0,2),(0,2),(checksum,4),(payload.count,4),(count,4),(path.count,2),(extra.count,2)] { locals.append(number(value,width)) }
            locals.append(path); locals.append(extra); locals.append(payload)
            for (value,width) in [(0x02014b50,4),(0x0314,2),(20,2),(flags,2),(method,2),(0,2),(0,2),(checksum,4),(payload.count,4),(count,4),(path.count,2),(extra.count,2),(0,2),(0,2),(0,2),(mode<<16,4),(offset,4)] { directory.append(number(value,width)) }
            directory.append(path); directory.append(extra)
        }
        var answer = locals + directory
        for (value,width) in [(0x06054b50,4),(0,2),(0,2),(names.count,2),(names.count,2),(directory.count,4),(locals.count,4),(0,2)] { answer.append(number(value,width)) }
        return answer
    }
    static func refuses(_ name: String, _ bytes: Data, limits: UpdateArchiveValidation.Limits = .init()) {
        do { try UpdateArchiveValidation.validate(bytes, bundleName: "Test.app", limits: limits); fatalError("Accepted \(name)") }
        catch { assertions += 1 }
    }
    static func main() async throws {
        let valid = zip()
        try UpdateArchiveValidation.validate(valid, bundleName: "Test.app")
        assertions += 1
        for mode in [0xa000,0x1000,0x2000,0x6000,0xc000] { refuses("non-regular file kind",zip(mode:mode)) }
        for path in ["../evil","Test.app/../evil","/Test.app/evil","Other.app/file","Test.app/./file","Test.app//file","Test.app/a:fork","Test.app/a\0x"] { refuses("unsafe path",zip([path])) }
        refuses("duplicate",zip(["Test.app/a","Test.app/a"]))
        refuses("case collision",zip(["Test.app/a","Test.app/A"]))
        refuses("encryption",zip(flags:1))
        refuses("unknown flags",zip(flags:0x4000))
        refuses("unsupported compression",zip(method:12))
        refuses("ZIP64 extra",zip(extra:number(1,2)+number(0,2)))
        refuses("Unix link extra",zip(extra:number(0x000d,2)+number(0,2)))
        refuses("ASI Unix mode extra",zip(extra:number(0x756e,2)+number(0,2)))
        refuses("alternate path extra",zip(extra:number(0x7075,2)+number(0,2)))
        refuses("advertised file expansion",zip(expanded:101),limits:.init(entries:20_000,file:100,total:1000))
        refuses("total expansion",zip(["Test.app/a","Test.app/b"],expanded:100),limits:.init(entries:20_000,file:100,total:199))
        refuses("entry count",zip(["Test.app/a","Test.app/b"]),limits:.init(entries:1,file:100,total:1000))
        var altered = valid; set(&altered,valid.count-12,0xffff,2); refuses("ZIP64 sentinel",altered)
        altered = valid; set(&altered,valid.count-18,1,2); refuses("multidisk",altered)
        altered = valid; altered[30] = 0x58; refuses("local and central names",altered)
        altered = valid; set(&altered,6,8,2); refuses("local flags mismatch",altered)
        altered = valid; set(&altered,18,99); refuses("local size mismatch",altered)
        altered = valid; altered[30+"Test.app/file".utf8.count] ^= 1; refuses("payload checksum",altered)
        altered = valid; set(&altered,valid.count-6,0); refuses("wrong directory offset",altered)
        var descriptor = zip(flags:8)
        let payloadEnd = 30 + "Test.app/file".utf8.count + 5
        descriptor.insert(contentsOf: number(crc(Data("hello".utf8)),4)+number(5,4)+number(5,4),at:payloadEnd)
        set(&descriptor,descriptor.count-6,payloadEnd+12)
        try UpdateArchiveValidation.validate(descriptor,bundleName:"Test.app"); assertions += 1
        set(&descriptor,payloadEnd,0); refuses("descriptor checksum mismatch",descriptor)
        var overlap=zip(["Test.app/a","Test.app/b"])
        let localSize=30+"Test.app/a".utf8.count+5, central=localSize*2, dataStart=30+"Test.app/a".utf8.count
        let covering=central-dataStart, coveringCRC=crc(overlap.subdata(in:dataStart..<central))
        for offset in [0,central] {
            let header=offset==0 ? 0 : 2
            set(&overlap,offset+14+header,coveringCRC)
            set(&overlap,offset+18+header,covering)
            set(&overlap,offset+22+header,covering)
        }
        refuses("overlapping payload ranges",overlap)
        var gap=valid; gap.insert(0,at:payloadEnd);set(&gap,gap.count-6,payloadEnd+1)
        refuses("hidden unaccounted data",gap)
        // Stored payload lying about expansion is rejected independently of CRC.
        refuses("lying stored size",zip(payload:Data(repeating:1,count:10_000),expanded:1))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("zip-security-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:folder.appendingPathComponent("Test.app"),withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let file=folder.appendingPathComponent("Test.app/large")
        try Data(repeating:65,count:2*1024*1024).write(to:file)
        let process=Process(); process.executableURL=URL(fileURLWithPath:"/usr/bin/zip"); process.currentDirectoryURL=folder
        process.arguments=["-q","-r","deflated.zip","Test.app"]; try process.run(); process.waitUntilExit()
        var deflated=try Data(contentsOf:folder.appendingPathComponent("deflated.zip"))
        try UpdateArchiveValidation.validate(deflated,bundleName:"Test.app"); assertions += 1
        // Rewrite declared sizes in both headers, leaving the compressed bomb intact.
        var cursor=0
        while cursor+46<deflated.count {
            let signature=Array(deflated[cursor..<cursor+4])
            if signature == [0x50,0x4b,0x01,0x02] {
                let local=(0..<4).reduce(0){$0|Int(deflated[cursor+42+$1])<<(8*$1)}
                let size=(0..<4).reduce(0){$0|Int(deflated[cursor+24+$1])<<(8*$1)}
                if size>1000 {set(&deflated,cursor+24,1);set(&deflated,local+22,1)}
            }
            cursor += 1
        }
        refuses("actual inflate exceeds declared size",deflated)
        let configuration=URLSessionConfiguration.ephemeral; configuration.protocolClasses=[ChunkProtocol.self]
        let session=URLSession(configuration:configuration)
        for path in ["/length","/chunked"] {
            let destination=folder.appendingPathComponent(path.dropFirst()+".download")
            do {
                _ = try await BoundedDownload.fetch(URLRequest(url:URL(string:"https://fixture.invalid"+path)!),using:session,to:destination,limit:8192)
                fatalError("Unbounded download accepted")
            } catch UpdateFailure.archiveTooLarge { assertions += 1 }
            let size=(try FileManager.default.attributesOfItem(atPath:destination.path)[.size] as! NSNumber).intValue
            check(size<=8192,"Never writes beyond limit")
        }
        print("Archive security tests passed: \(assertions) assertions")
    }
}

final class ChunkProtocol: URLProtocol, @unchecked Sendable {
    private let lock=NSLock(); private var stopped=false
    override class func canInit(with request:URLRequest)->Bool {true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
    override func startLoading() {
        let fields=request.url!.path == "/length" ? ["Content-Length":"1000000"] : [:]
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:"HTTP/1.1",headerFields:fields)!,cacheStoragePolicy:.notAllowed)
        DispatchQueue.global().async { [self] in
            for _ in 0..<100 {
                lock.lock(); let finished=stopped;lock.unlock();if finished{return}
                client?.urlProtocol(self,didLoad:Data(repeating:0,count:4096));Thread.sleep(forTimeInterval:0.002)
            }
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading(){lock.lock();stopped=true;lock.unlock()}
}
