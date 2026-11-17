import Foundation

/// UTF8 identity matches Go/JavaScript object keys, including canonically equivalent names.
public struct TaskArchiveCountMap: Decodable, Sendable {
    public struct Entry: Identifiable, Sendable {
        public let name: String
        public let count: Int64
        public var id: Data { Data(name.utf8) }
    }
    public let entries: [Entry]
    public var count: Int { entries.count }
    public var isEmpty: Bool { entries.isEmpty }
    public var values: [Int64] { entries.map(\.count) }
    public subscript(_ name: String) -> Int64? { entries.first { $0.name.utf8.elementsEqual(name.utf8) }?.count }
    init(_ entries: [Entry] = []) { self.entries = entries }
    public init(from decoder: any Decoder) throws {
        let path = decoder.codingPath.map { key -> String in
            if let index = key.intValue { return "#\(index)" }
            switch key.stringValue { case "dataCounts": return "data_counts"; case "aggregateStats": return "aggregate_stats"; default: return key.stringValue }
        }.joined(separator:"/")
        guard let maps = decoder.userInfo[TaskArchiveWire.key] as? [String:TaskArchiveCountMap], let map = maps[path] else { throw BackendAPIError.invalidResponse }
        self = map
    }
}

/// Pre-extract only count maps from bounded raw JSON before Foundation collapses Unicode keys.
/// String token decoding delegates UTF8/escapes/surrogate validation to JSONDecoder.
enum TaskArchiveWire {
    static var key: CodingUserInfoKey { CodingUserInfoKey(rawValue:"artex.archive.raw-counts")! }
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard data.count <= 4 * 1024 * 1024 else { throw BackendAPIError.invalidResponse }
        var scanner = Scanner(bytes:Array(data)); let maps = try scanner.scan()
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase; decoder.userInfo[key] = maps
        return try decoder.decode(type,from:data)
    }
    private struct Scanner {
        let bytes: [UInt8]
        var index = 0
        var maps: [String:TaskArchiveCountMap] = [:]
        mutating func scan() throws -> [String:TaskArchiveCountMap] {
            try value(path:[],depth:0); space(); guard index == bytes.count else { throw BackendAPIError.invalidResponse }; return maps
        }
        mutating func space() { while index < bytes.count, [9,10,13,32].contains(bytes[index]) { index += 1 } }
        mutating func take(_ byte: UInt8) throws {
            space(); guard index < bytes.count, bytes[index] == byte else { throw BackendAPIError.invalidResponse }; index += 1
        }
        mutating func literal(_ text: String) throws {
            let value = Array(text.utf8)
            guard index+value.count <= bytes.count, bytes[index..<index+value.count].elementsEqual(value) else { throw BackendAPIError.invalidResponse }; index += value.count
        }
        mutating func string() throws -> String {
            space(); let start = index; try take(34)
            while index < bytes.count {
                if bytes[index] == 34 {
                    index += 1; return try JSONDecoder().decode(String.self,from:Data(bytes[start..<index]))
                }
                if bytes[index] == 92 { index += 1; guard index < bytes.count else { throw BackendAPIError.invalidResponse } }
                index += 1
            }
            throw BackendAPIError.invalidResponse
        }
        func digit(_ byte: UInt8) -> Bool { (48...57).contains(byte) }
        mutating func number() throws -> String {
            let start = index
            if index < bytes.count, bytes[index] == 45 { index += 1 }
            guard index < bytes.count, digit(bytes[index]) else { throw BackendAPIError.invalidResponse }
            if bytes[index] == 48 { index += 1 } else { while index < bytes.count, digit(bytes[index]) { index += 1 } }
            if index < bytes.count, bytes[index] == 46 {
                index += 1; let first = index; while index < bytes.count, digit(bytes[index]) { index += 1 }
                guard index > first else { throw BackendAPIError.invalidResponse }
            }
            if index < bytes.count, bytes[index] == 69 || bytes[index] == 101 {
                index += 1
                if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 { index += 1 }
                let first = index; while index < bytes.count, digit(bytes[index]) { index += 1 }
                guard index > first else { throw BackendAPIError.invalidResponse }
            }
            return String(decoding:bytes[start..<index],as:UTF8.self)
        }
        func recordPath(_ path: [String]) -> Bool { path.isEmpty || path.count == 2 && path[0] == "items" && path[1].hasPrefix("#") }
        func isCountMap(_ path: [String]) -> Bool {
            if path.last == "data_counts", recordPath(Array(path.dropLast())) { return true }
            return path.count >= 2 && ["skills","tools","findings"].contains(path.last!) && path[path.count-2] == "aggregate_stats" && recordPath(Array(path.dropLast(2)))
        }
        mutating func value(path: [String], depth: Int) throws {
            guard depth <= 128 else { throw BackendAPIError.invalidResponse }
            space(); guard index < bytes.count else { throw BackendAPIError.invalidResponse }
            switch bytes[index] {
            case 123: try object(path:path,depth:depth)
            case 91:
                try take(91); space(); if index < bytes.count, bytes[index] == 93 { index += 1; return }
                var offset = 0
                while true {
                    try value(path:path+["#\(offset)"],depth:depth+1); offset += 1; space()
                    guard index < bytes.count else { throw BackendAPIError.invalidResponse }
                    if bytes[index] == 93 { index += 1; return }; try take(44)
                }
            case 34: _ = try string()
            case 110: try literal("null")
            case 116: try literal("true")
            case 102: try literal("false")
            default: _ = try number()
            }
        }
        mutating func object(path: [String], depth: Int) throws {
            try take(123); space(); let counts = isCountMap(path)
            var entries: [TaskArchiveCountMap.Entry] = [], keys = Set<Data>()
            if index < bytes.count, bytes[index] == 125 {
                index += 1; if counts { maps[path.joined(separator:"/")] = .init() }; return
            }
            while true {
                let name = try string(); guard keys.insert(Data(name.utf8)).inserted else { throw BackendAPIError.invalidResponse }; try take(58); space()
                if counts {
                    let raw = try number()
                    guard raw.utf8.allSatisfy({digit($0)}), let count = Int64(raw), count >= 0 else { throw BackendAPIError.invalidResponse }
                    entries.append(.init(name:name,count:count))
                } else {
                    if recordPath(path) {
                        let folded = name.replacingOccurrences(of:"_",with:"").lowercased()
                        if folded == "datacounts", name != "data_counts" { throw BackendAPIError.invalidResponse }
                        if folded == "aggregatestats", name != "aggregate_stats" { throw BackendAPIError.invalidResponse }
                    }
                    try value(path:path+[name],depth:depth+1)
                }
                space(); guard index < bytes.count else { throw BackendAPIError.invalidResponse }
                if bytes[index] == 125 {
                    index += 1; if counts { maps[path.joined(separator:"/")] = .init(entries) }; return
                }
                try take(44)
            }
        }
    }
}
