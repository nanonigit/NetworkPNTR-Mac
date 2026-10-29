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
        for line in raw.unicodeScalars.split(whereSeparator: { [10, 13, 0x2028, 0x2029].contains($0.value) }) {
            var values = line.makeIterator()
            guard [72, 104].contains(values.next()?.value ?? 0), [79, 111].contains(values.next()?.value ?? 0),
                  [83, 115].contains(values.next()?.value ?? 0), [84, 116].contains(values.next()?.value ?? 0) else { continue }
            while let value = values.next() {
                if value.value == 58 { return true }
                if !ChatText.trim(String(value)).isEmpty { break }
            }
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
