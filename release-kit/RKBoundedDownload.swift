import Foundation

/// Writes bounded chunks directly to disk; never asks URLSession to accumulate an
/// untrusted response or finish a potentially unbounded download before checking.
final class BoundedDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let limit: Int
    private let output: FileHandle
    private var count = 0
    private var response: URLResponse?
    private var failure: Error?
    private var continuation: CheckedContinuation<URLResponse, Error>?

    private init(to file: URL, limit: Int) throws {
        self.limit = limit
        guard FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw UpdateFailure.offline("The download could not be saved.")
        }
        output = try FileHandle(forWritingTo: file)
    }

    static func fetch(_ request: URLRequest, using session: URLSession, to file: URL, limit: Int) async throws -> URLResponse {
        let delegate = try BoundedDownload(to: file, limit: limit)
        if let url = request.url, url.isFileURL {
            defer { try? delegate.output.close() }
            let input = try FileHandle(forReadingFrom: url)
            defer { try? input.close() }
            while let data = try input.read(upToCount: 65_536), !data.isEmpty {
                try Task.checkCancellation()
                try delegate.append(data)
            }
            return URLResponse(url: url, mimeType: nil, expectedContentLength: delegate.count, textEncodingName: nil)
        }
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let bounded = URLSession(configuration: session.configuration, delegate: delegate, delegateQueue: queue)
        defer { bounded.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            bounded.dataTask(with: request).resume()
        }
    }

    private func append(_ data: Data) throws {
        guard data.count <= limit - count else { throw UpdateFailure.archiveTooLarge(count + data.count) }
        try output.write(contentsOf: data)
        count += data.count
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.response = response
        guard response.expectedContentLength <= Int64(limit) else {
            failure = UpdateFailure.archiveTooLarge(Int(clamping: response.expectedContentLength))
            completionHandler(.cancel); return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard failure == nil else { return }
        do { try append(data) }
        catch { failure = error; dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? output.close()
        if let failure = failure ?? error { continuation?.resume(throwing: failure) }
        else if let response { continuation?.resume(returning: response) }
        else { continuation?.resume(throwing: UpdateFailure.offline("The download had no response.")) }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" ? request : nil)
    }
}
