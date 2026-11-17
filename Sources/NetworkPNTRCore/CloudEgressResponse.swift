import Foundation

enum CloudEgressResponseType: Equatable, Sendable {
    case json
    case eventStream
}

enum CloudEgressResponseEvent: Equatable, Sendable {
    case head(status: Int, type: CloudEgressResponseType?)
    case body(Data)
    case end
}

enum CloudEgressResponseError: Error, Equatable {
    case invalidFraming
    case limit
    case redirect
}

struct CloudEgressResponseBoundary: Error {}

extension CloudEgressTransport {
    // A close-delimited response requires authenticated TLS closure. For a
    // single-use connection, explicit framing can end the TLS read earlier.
    static func frameResponse(
        receive: @escaping (CloudEgressResponseEvent) throws -> Void,
        stopAtBoundary: Bool = false,
        read: (_ consume: @escaping (Data) throws -> Void) throws -> Void
    ) throws {
        let parser = CloudEgressResponseFramer(receive: receive)
        defer { parser.invalidate() }
        do {
            try read { bytes in
                try parser.consume(bytes)
                if stopAtBoundary, parser.hasExplicitBoundary { throw CloudEgressResponseBoundary() }
            }
        } catch is CloudEgressResponseBoundary {
            // Fixture reads use the same signal to stop supplying bytes.
        }
        try parser.finish()
    }
}

private final class CloudEgressResponseFramer {
    private enum Phase {
        case status, fields, fixed(Int), untilClose
        case chunkSize, chunkBody(Int), chunkTerminator, trailers
        case done, terminal
    }

    private struct Head {
        let status: Int
        let http11: Bool
        var fields: [String: String] = [:]
    }

    private static let bodyLimit = 16 * 1024 * 1024
    private static let headerLimit = 32 * 1024
    private static let trailerLimit = 8 * 1024
    private static let chunkLineLimit = 1024
    private static let retainedFields: Set<String> = [
        "content-length", "transfer-encoding", "content-type", "content-encoding"
    ]
    private static let tokenPunctuation = Set("!#$%&'*+-.^_`|~".utf8)

    private let receive: (CloudEgressResponseEvent) throws -> Void
    private var phase = Phase.status
    private var head: Head?
    private var line = [UInt8]()
    private var sectionBytes = 0
    private var bodyBytes = 0
    private var interimCount = 0

    init(receive: @escaping (CloudEgressResponseEvent) throws -> Void) {
        self.receive = receive
    }

    func invalidate() {
        phase = .terminal
        line.removeAll()
        head = nil
    }

    func consume(_ bytes: Data) throws {
        do {
            var cursor = bytes.startIndex
            while cursor < bytes.endIndex {
                try step(bytes, cursor: &cursor)
            }
        } catch {
            invalidate()
            throw error
        }
    }

    private func step(_ bytes: Data, cursor: inout Int) throws {
        switch phase {
        case .status:
            guard let value = try readLine(bytes, cursor: &cursor, limit: Self.headerLimit, countSection: true) else { return }
            head = try Self.parseStatus(value)
            phase = .fields
        case .fields:
            guard let value = try readLine(bytes, cursor: &cursor, limit: Self.headerLimit, countSection: true) else { return }
            if value.isEmpty { try finishHead() }
            else { try acceptField(value) }
        case .fixed(let remaining):
            let written = try emitBody(bytes, cursor: &cursor, maximum: remaining)
            phase = written == remaining ? .done : .fixed(remaining - written)
        case .untilClose:
            try emitBody(bytes, cursor: &cursor, maximum: bytes.endIndex - cursor)
        case .chunkSize:
            guard let value = try readLine(bytes, cursor: &cursor, limit: Self.chunkLineLimit) else { return }
            let length = try chunkLength(value)
            phase = length == 0 ? .trailers : .chunkBody(length)
        case .chunkBody(let remaining):
            let written = try emitBody(bytes, cursor: &cursor, maximum: remaining)
            phase = written == remaining ? .chunkTerminator : .chunkBody(remaining - written)
        case .chunkTerminator:
            guard let value = try readLine(bytes, cursor: &cursor, limit: 2) else { return }
            guard value.isEmpty else { throw CloudEgressResponseError.invalidFraming }
            phase = .chunkSize
        case .trailers:
            guard let value = try readLine(bytes, cursor: &cursor, limit: Self.trailerLimit, countSection: true) else { return }
            if value.isEmpty {
                phase = .done
            } else {
                let (name, _) = try Self.parseField(value)
                guard !Self.retainedFields.contains(name) else { throw CloudEgressResponseError.invalidFraming }
            }
        case .done, .terminal:
            throw CloudEgressResponseError.invalidFraming
        }
    }

    var hasExplicitBoundary: Bool {
        if case .done = phase { return true }
        return false
    }

    func finish() throws {
        switch phase {
        case .done, .untilClose:
            invalidate()
            try receive(.end)
        default:
            throw CloudEgressResponseError.invalidFraming
        }
    }

    private func readLine(_ bytes: Data, cursor: inout Int, limit: Int, countSection: Bool = false) throws -> String? {
        while cursor < bytes.endIndex {
            let byte = bytes[cursor]
            cursor += 1
            guard line.count < limit else { throw CloudEgressResponseError.limit }
            if countSection {
                guard sectionBytes < limit else { throw CloudEgressResponseError.limit }
                sectionBytes += 1
            }
            if line.last == 13 {
                guard byte == 10 else { throw CloudEgressResponseError.invalidFraming }
                let value = String(decoding: line.dropLast(), as: UTF8.self)
                line.removeAll(keepingCapacity: true)
                return value
            }
            guard byte != 10 else { throw CloudEgressResponseError.invalidFraming }
            line.append(byte)
        }
        return nil
    }

    private static func parseStatus(_ line: String) throws -> Head {
        let bytes = Array(line.utf8)
        let version = String(decoding: bytes.prefix(9), as: UTF8.self)
        guard bytes.count >= 12, version == "HTTP/1.1 " || version == "HTTP/1.0 ",
              bytes[9..<12].allSatisfy({ (48...57).contains($0) }),
              bytes.count == 12 || (bytes[12] == 32 && validFieldValue(bytes.dropFirst(13))),
              let status = Int(String(decoding: bytes[9..<12], as: UTF8.self)),
              (100...599).contains(status) else { throw CloudEgressResponseError.invalidFraming }
        guard !(300...399).contains(status) else { throw CloudEgressResponseError.redirect }
        return Head(status: status, http11: version == "HTTP/1.1 ")
    }

    private static func validFieldValue(_ bytes: some Sequence<UInt8>) -> Bool {
        bytes.allSatisfy { $0 == 9 || ($0 >= 32 && $0 != 127) }
    }

    private static func isTokenByte(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) || tokenPunctuation.contains(byte)
    }

    private static func parseField(_ line: String) throws -> (String, String) {
        guard let colon = line.firstIndex(of: ":"), colon != line.startIndex,
              line[..<colon].utf8.allSatisfy(isTokenByte) else { throw CloudEgressResponseError.invalidFraming }
        let value = line[line.index(after: colon)...]
        guard validFieldValue(value.utf8) else { throw CloudEgressResponseError.invalidFraming }
        return (line[..<colon].lowercased(), value.trimmingCharacters(in: CharacterSet(charactersIn: " \t")))
    }

    private func acceptField(_ line: String) throws {
        let (name, value) = try Self.parseField(line)
        guard Self.retainedFields.contains(name) else { return }
        guard head?.fields[name] == nil else { throw CloudEgressResponseError.invalidFraming }
        head?.fields[name] = value
    }

    private func finishHead() throws {
        guard let head else { throw CloudEgressResponseError.invalidFraming }
        self.head = nil
        sectionBytes = 0
        let transfer = try asciiCoding(head.fields["transfer-encoding"])
        let length = try contentLength(head.fields["content-length"])
        if head.status < 200 {
            guard head.http11, [100, 102, 103].contains(head.status), length == nil, transfer == nil,
                  interimCount < 4 else { throw CloudEgressResponseError.invalidFraming }
            interimCount += 1
            phase = .status
            return
        }

        let encoding = try asciiCoding(head.fields["content-encoding"])
        guard encoding == nil || encoding == "identity" else { throw CloudEgressResponseError.invalidFraming }
        if [204, 205].contains(head.status) {
            guard transfer == nil, length == nil || length == 0 else { throw CloudEgressResponseError.invalidFraming }
            phase = .done
        } else if let transfer {
            guard head.http11, transfer == "chunked", length == nil else { throw CloudEgressResponseError.invalidFraming }
            phase = .chunkSize
        } else if let length {
            phase = length == 0 ? .done : .fixed(length)
        } else {
            phase = .untilClose
        }
        let type = head.fields["content-type"]?.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first?
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t")).lowercased()
        let output: CloudEgressResponseType?
        switch type {
        case "application/json": output = .json
        case "text/event-stream": output = .eventStream
        default: output = nil
        }
        try receive(.head(status: head.status, type: output))
    }

    private func contentLength(_ text: String?) throws -> Int? {
        guard let text else { return nil }
        guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }) else { throw CloudEgressResponseError.invalidFraming }
        guard let length = Int(text), length <= Self.bodyLimit else { throw CloudEgressResponseError.limit }
        return length
    }

    private func asciiCoding(_ text: String?) throws -> String? {
        guard let text else { return nil }
        guard text.utf8.allSatisfy({ $0 < 128 }) else { throw CloudEgressResponseError.invalidFraming }
        return text.lowercased()
    }

    private func chunkLength(_ line: String) throws -> Int {
        let bytes = Array(line.utf8)
        let size = bytes.prefix(while: {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        })
        guard !size.isEmpty, Self.validChunkExtensions(bytes.dropFirst(size.count)) else {
            throw CloudEgressResponseError.invalidFraming
        }
        guard let length = Int(String(decoding: size, as: UTF8.self), radix: 16), length <= Self.bodyLimit - bodyBytes else {
            throw CloudEgressResponseError.limit
        }
        return length
    }

    private static func validChunkExtensions(_ bytes: ArraySlice<UInt8>) -> Bool {
        func skipSpace(_ input: ArraySlice<UInt8>) -> ArraySlice<UInt8> {
            input.drop(while: { $0 == 32 || $0 == 9 })
        }
        var rest = bytes
        while !rest.isEmpty {
            rest = skipSpace(rest)
            guard rest.popFirst() == 59 else { return false } // semicolon
            rest = skipSpace(rest)
            let name = rest.prefix(while: isTokenByte)
            guard !name.isEmpty else { return false }
            rest = rest.dropFirst(name.count)
            let afterName = skipSpace(rest)
            guard afterName.first == 61 else { continue } // optional equals
            rest = skipSpace(afterName.dropFirst())
            if rest.first == 34 {
                rest = rest.dropFirst()
                guard consumeQuotedExtension(&rest) else { return false }
            } else {
                let value = rest.prefix(while: isTokenByte)
                guard !value.isEmpty else { return false }
                rest = rest.dropFirst(value.count)
            }
        }
        return true
    }

    private static func consumeQuotedExtension(_ bytes: inout ArraySlice<UInt8>) -> Bool {
        while let byte = bytes.popFirst() {
            if byte == 34 { return true }
            if byte == 92 {
                guard let escaped = bytes.popFirst(), escaped == 9 || (escaped >= 32 && escaped != 127) else { return false }
            } else if byte != 9 && (byte < 32 || byte == 127) {
                return false
            }
        }
        return false
    }

    @discardableResult
    private func emitBody(_ bytes: Data, cursor: inout Int, maximum: Int) throws -> Int {
        let count = min(maximum, bytes.endIndex - cursor)
        guard count <= Self.bodyLimit - bodyBytes else { throw CloudEgressResponseError.limit }
        try receive(.body(Data(bytes[cursor..<(cursor + count)])))
        cursor += count
        bodyBytes += count
        return count
    }
}
