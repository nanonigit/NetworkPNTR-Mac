import CryptoKit
import Foundation

public struct BackendDownloadResult: Sendable, Equatable {
    public let status: Int
    public let byteCount: Int64
    public let sha256: String
    public init(status: Int, byteCount: Int64, sha256: String) {
        self.status = status; self.byteCount = byteCount; self.sha256 = sha256
    }
}

/// Single-consumer response digest. No success or error body is retained.
/// The received stream is verified, not a concurrently modified file snapshot.
final class BackendDownloadDigest {
    static let maximumBytes: Int64 = 128 * 1024 * 1024
    private let expectedSize: Int64
    private let byteCeiling: Int64
    private let onBody: (@Sendable (Data) throws -> Void)?
    private var header = Data()
    private var status: Int?
    private var length: Int64?
    private var count: Int64 = 0
    private var hash = SHA256()
    private var terminal = false
    private var cancelled = false
    var bufferedBytes: Int { header.count }
    var isComplete: Bool { !terminal && status != nil && length == count }
    init(expectedSize: Int64, maximumBytes: Int64 = BackendDownloadDigest.maximumBytes, onBody: (@Sendable (Data) throws -> Void)? = nil) throws {
        guard expectedSize >= 0, maximumBytes >= expectedSize else { throw BackendAPIError.invalidResponse }
        self.expectedSize = expectedSize; byteCeiling = maximumBytes; self.onBody = onBody
    }
    func cancel() { cancelled = true; terminate() }
    func consume(_ bytes: Data) throws {
        try checkActive()
        do {
            try Task.checkCancellation()
            guard bytes.count <= 65536 else { throw BackendAPIError.invalidResponse }
            var cursor = bytes.startIndex
            if status == nil {
                while cursor < bytes.endIndex {
                    guard header.count < 65536 else { throw BackendAPIError.invalidResponse }
                    header.append(bytes[cursor]); cursor += 1
                    if header.count >= 4 && header.suffix(4).elementsEqual([13,10,13,10]) {
                        try parseHeader()
                        header.removeAll(keepingCapacity: false)
                        break
                    }
                }
            }
            if cursor < bytes.endIndex {
                guard let status else { throw BackendAPIError.invalidResponse }
                let limit = length ?? (status == 200 ? byteCeiling : 4 * 1024 * 1024)
                let size = Int64(bytes.endIndex - cursor)
                guard size <= limit - count else { throw BackendAPIError.invalidResponse }
                if status == 200 { try onBody?(Data(bytes[cursor...])) }
                hash.update(data: bytes[cursor...]); count += size
            }
        } catch { terminate(); throw error }
    }
    func finish() throws -> BackendDownloadResult {
        try checkActive()
        defer { terminate() }
        try Task.checkCancellation()
        guard let status, length == nil || length == count else { throw BackendAPIError.invalidResponse }
        return BackendDownloadResult(status: status, byteCount: count,
            sha256: hash.finalize().map { String(format: "%02x", $0) }.joined())
    }
    private func checkActive() throws {
        if cancelled { throw CancellationError() }
        guard !terminal else { throw BackendAPIError.invalidResponse }
    }
    private func terminate() { terminal = true; header.removeAll(keepingCapacity: false); hash = SHA256() }
    private func parseHeader() throws {
        guard let text = String(data: header.dropLast(4), encoding: .isoLatin1) else { throw BackendAPIError.invalidResponse }
        let lines = text.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ", omittingEmptySubsequences: true)
        guard first.count >= 2, ["HTTP/1.0", "HTTP/1.1"].contains(first[0]),
              first[1].utf8.count == 3, first[1].utf8.allSatisfy({ (48...57).contains($0) }),
              let code = Int(first[1]), code == 200 || (300...599).contains(code) else { throw BackendAPIError.invalidResponse }
        var fields: [String: String] = [:]
        let punctuation = Array("!#$%&'*+-.^_`|~".utf8)
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex,
                  line[..<colon].utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || punctuation.contains($0) }),
                  line[line.index(after: colon)...].utf8.allSatisfy({ $0 == 9 || ($0 >= 32 && $0 != 127) }) else { throw BackendAPIError.invalidResponse }
            let name = line[..<colon].lowercased()
            if ["content-length", "transfer-encoding", "content-encoding"].contains(name), fields[name] != nil { throw BackendAPIError.invalidResponse }
            fields[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard fields["transfer-encoding"] == nil,
              fields["content-encoding"] == nil || fields["content-encoding"]?.lowercased() == "identity" else { throw BackendAPIError.invalidResponse }
        if let value = fields["content-length"] {
            guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }), let size = Int64(value),
                  size <= (code == 200 ? byteCeiling : 4 * 1024 * 1024),
                  code != 200 || size == expectedSize else { throw BackendAPIError.invalidResponse }
            length = size
        } else if code == 200 { throw BackendAPIError.invalidResponse }
        status = code
    }
}
