import Darwin
import Foundation

public struct CompanyScopeText: Sendable {
    public let rules: [CompanyScopeInput]
    public let invalidLines: [Int]

    public init(_ text: String, preserving saved: [AssetCatalogCompany.ScopeRule] = []) {
        let kinds = Dictionary(grouping: saved, by: { ChatText.trim($0.raw) })
        var consumed: [String: Int] = [:]
        var rules: [CompanyScopeInput] = []
        var invalid: [Int] = []
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for (index, raw) in lines.enumerated() {
            let value = ChatText.trim(raw)
            guard !value.isEmpty else { continue }
            let offset = consumed[value, default: 0]
            let savedKind = kinds[value]?.dropFirst(offset).first?.kind
            consumed[value] = offset + 1
            if let rule = Self.parse(value, preserving: savedKind) {
                rules.append(rule)
            } else {
                invalid.append(index + 1)
            }
        }
        self.rules = rules
        invalidLines = invalid
    }

    private static func parse(_ value: String, preserving kind: CompanyScopeInput.Kind?) -> CompanyScopeInput? {
        guard value.unicodeScalars.count <= 1_024 else { return nil }
        if let kind { return valid(value, as: kind) ? .init(kind: kind, value: value) : nil }

        if let separator = value.lastIndex(of: "/") {
            let address = String(value[..<separator])
            if addressVersion(address) != nil || resemblesAddress(address) {
                return valid(value, as: .cidr) ? .init(kind: .cidr, value: value) : nil
            }
        }
        if addressVersion(value) != nil { return .init(kind: .ip, value: value) }
        if resemblesAddress(value) { return nil }

        if value.contains("://") || (value.contains(".") && !value.contains(where: \.isWhitespace)) {
            guard let host = hostname(value) else { return nil }
            if addressVersion(host) != nil { return .init(kind: .ip, value: host) }
            return validDomain(host) ? .init(kind: .domain, value: value) : nil
        }

        let kind: CompanyScopeInput.Kind = value.localizedCaseInsensitiveContains("icp") || value.contains("备案")
            ? .icp : .keyword
        return .init(kind: kind, value: value)
    }

    private static func valid(_ value: String, as kind: CompanyScopeInput.Kind) -> Bool {
        switch kind {
        case .domain:
            guard let host = hostname(value), addressVersion(host) == nil else { return false }
            return validDomain(host)
        case .ip:
            return addressVersion(value) != nil
        case .cidr:
            guard let separator = value.lastIndex(of: "/"),
                  let version = addressVersion(String(value[..<separator])) else { return false }
            let suffix = value[value.index(after: separator)...]
            guard !suffix.isEmpty, suffix.utf8.allSatisfy({ (48...57).contains($0) }),
                  let prefix = Int(suffix) else { return false }
            return version == 4 ? (16...32).contains(prefix) : (32...128).contains(prefix)
        case .icp, .keyword:
            return true
        }
    }

    private static func addressVersion(_ value: String) -> Int? {
        guard !value.utf8.contains(0) else { return nil }
        var ipv4 = in_addr()
        if inet_pton(AF_INET, value, &ipv4) == 1 { return 4 }
        var ipv6 = in6_addr()
        if inet_pton(AF_INET6, value, &ipv6) == 1 { return 6 }
        return nil
    }

    private static func resemblesAddress(_ value: String) -> Bool {
        guard !value.contains("://"), !value.contains(where: \.isWhitespace) else { return false }
        if value.contains("."), value.utf8.allSatisfy({ $0 == 46 || (48...57).contains($0) }) { return true }
        let parts = value.components(separatedBy: ":")
        guard parts.count >= 3 else { return false }
        var hexSegments = 0
        for part in parts {
            if part.isEmpty {
                if hexSegments > 0 || value.hasPrefix("::") { return true }
                continue
            }
            guard part.utf8.count <= 4, part.utf8.allSatisfy({ byte in
                (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
            }) else { return false }
            hexSegments += 1
            if hexSegments >= 2 { return true }
        }
        return false
    }

    private static func hostname(_ value: String) -> String? {
        guard !value.contains(where: \.isWhitespace) else { return nil }
        let candidate: String
        if value.hasPrefix("//") { candidate = "http:" + value }
        else if value.contains("://") { candidate = value }
        else { candidate = "http://" + value }
        guard var host = URL(string: candidate)?.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if host.hasSuffix(".") { host.removeLast() }
        return host
    }

    private static func validDomain(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        return host.utf8.count <= 253 && labels.count >= 2 && labels.allSatisfy { label in
            !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-"
                && label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
        }
    }
}
