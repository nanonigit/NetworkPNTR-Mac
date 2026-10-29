import ArtexCore
import Foundation

/// Display-only legacy Host completion. Never mutate the backend detail or interpret packet text as UI copy.
enum TrafficPresentation {
    static func request(_ raw: String, url: String, host fallback: String) -> String {
        guard !ChatText.trim(raw).isEmpty, !hasHost(raw) else { return raw }
        var host = fallback
        if let parts = URLComponents(string: url), let scheme = parts.scheme,
           let parsed = parts.url?.host(), !parsed.isEmpty,
           parts.port.map({ (0...65535).contains($0) }) ?? true {
            host = parsed.lowercased()
            if host.contains(":"), !host.hasPrefix("[") { host = "[" + host + "]" }
            if let port = parts.port, !(scheme.lowercased() == "http" && port == 80), !(scheme.lowercased() == "https" && port == 443) {
                host += ":" + String(port)
            }
        }
        let newline = raw.contains("\r\n") ? "\r\n" : "\n"
        guard let first = raw.range(of: newline) else { return raw + newline + "Host: " + host }
        return String(raw[..<first.upperBound]) + "Host: " + host + newline + String(raw[first.upperBound...])
    }
    private static func hasHost(_ raw: String) -> Bool {
        let values = Array(raw.unicodeScalars)
        for index in values.indices where index == 0 || [10, 13, 0x2028, 0x2029].contains(values[index - 1].value) {
            guard index + 4 < values.count,
                  [72, 104].contains(values[index].value), [79, 111].contains(values[index + 1].value),
                  [83, 115].contains(values[index + 2].value), [84, 116].contains(values[index + 3].value) else { continue }
            var cursor = index + 4
            while cursor < values.count, ChatText.trim(String(values[cursor])).isEmpty { cursor += 1 }
            if cursor < values.count, values[cursor].value == 58 { return true }
        }
        return false
    }
    static func status(_ value: TrafficStatusFilter?) -> String {
        switch value {
        case .success: "2xx"
        case .redirect: "3xx"
        case .clientError: "4xx"
        case .serverError: "5xx"
        default: "all"
        }
    }
}
