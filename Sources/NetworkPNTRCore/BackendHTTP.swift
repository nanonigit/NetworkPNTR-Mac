import Foundation

public enum BackendHTTPRequest {
    public static func make(method: String, path: String, body: Data?, bearer: String?) throws -> Data {
        guard ["GET", "POST", "PUT", "PATCH", "DELETE"].contains(method), path.hasPrefix("/api/"),
              path.utf8.allSatisfy({ $0 > 32 && $0 < 127 }), path.utf8.count <= 8192,
              (body?.count ?? 0) <= 4 * 1024 * 1024 else { throw RuntimeError.integrity("backend request") }
        var header = "\(method) \(path) HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\nAccept: application/json\r\nContent-Type: application/json\r\nContent-Length: \(body?.count ?? 0)\r\n"
        if let bearer {
            guard !bearer.isEmpty, bearer.utf8.count <= 8192,
                  bearer.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95, 126].contains($0) }) else { throw RuntimeError.integrity("session credential encoding") }
            header += "Authorization: Bearer \(bearer)\r\n"
        }
        return Data((header + "\r\n").utf8) + (body ?? Data())
    }
}

public struct BackendHTTPResponse: Sendable {
    public let status: Int
    public let body: Data
    public init(status: Int, body: Data) { self.status = status; self.body = body }
    public static func parse(_ wire: Data) throws -> Self {
        func invalid() -> RuntimeError { .integrity("backend HTTP framing") }
        guard wire.count <= 4 * 1024 * 1024,
              let separator = wire.range(of: Data("\r\n\r\n".utf8)), separator.lowerBound <= 65536,
              let header = String(data: wire[..<separator.lowerBound], encoding: .isoLatin1) else { throw invalid() }
        let lines = header.components(separatedBy: "\r\n")
        let statusLine = lines[0].split(separator: " ", omittingEmptySubsequences: true)
        guard statusLine.count >= 2, ["HTTP/1.1", "HTTP/1.0"].contains(statusLine[0]),
              statusLine[1].count == 3, let status = Int(statusLine[1]), (200...599).contains(status) else { throw invalid() }
        var fields: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex,
                  !line.contains("\n"), !line.contains("\r"), !line.hasPrefix(" "), !line.hasPrefix("\t") else { throw invalid() }
            let key = line[..<colon].lowercased()
            if ["content-length", "transfer-encoding"].contains(key), fields[key] != nil { throw invalid() }
            fields[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let body = Data(wire[separator.upperBound...])
        if let transfer = fields["transfer-encoding"] {
            guard transfer.lowercased() == "chunked", fields["content-length"] == nil else { throw invalid() }
            var cursor = 0
            var decoded = Data()
            func line() throws -> String {
                guard cursor <= body.count, let end = body.range(of: Data("\r\n".utf8), in: cursor..<body.count), end.lowerBound - cursor <= 8192,
                      let value = String(data: body[cursor..<end.lowerBound], encoding: .ascii) else { throw invalid() }
                cursor = end.upperBound
                return value
            }
            while true {
                let sizeText = try line().split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)[0]
                guard !sizeText.isEmpty, sizeText.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
                      let size = Int(sizeText, radix: 16), size <= 4 * 1024 * 1024 - decoded.count else { throw invalid() }
                if size == 0 {
                    while true {
                        let trailer = try line()
                        if trailer.isEmpty { break }
                        guard trailer.contains(":"), !trailer.hasPrefix(" "), !trailer.hasPrefix("\t") else { throw invalid() }
                    }
                    guard cursor == body.count else { throw invalid() }
                    return Self(status: status, body: decoded)
                }
                guard size <= body.count - cursor, body.count - cursor - size >= 2,
                      body[cursor + size..<cursor + size + 2] == Data("\r\n".utf8) else { throw invalid() }
                decoded.append(body[cursor..<cursor + size]); cursor += size + 2
            }
        }
        if let lengthText = fields["content-length"] {
            guard !lengthText.isEmpty, lengthText.utf8.allSatisfy({ (48...57).contains($0) }), let length = Int(lengthText), length == body.count else { throw invalid() }
        }
        return Self(status: status, body: body)
    }
}
