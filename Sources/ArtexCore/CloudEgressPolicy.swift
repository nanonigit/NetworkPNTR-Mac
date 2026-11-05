import Darwin
import Foundation
import Network
import Security

enum CloudEgressError: Error {
    case invalidRequest
    case invalidAddress
    case resolutionFailed
}

/// Wire IDs select an operation, never a guest-supplied URL or HTTP method.
enum CloudEgressRoute: String, CaseIterable, Sendable {
    case openAIModels = "openai.models", openAIChat = "openai.chat", openAIResponses = "openai.responses"
    case anthropicModels = "anthropic.models", anthropicMessages = "anthropic.messages"
    case geminiModels = "gemini.models", geminiChat = "gemini.chat"
    case groqModels = "groq.models", groqChat = "groq.chat"

    var hostname: String {
        switch self {
        case .openAIModels, .openAIChat, .openAIResponses: "api.openai.com"
        case .anthropicModels, .anthropicMessages: "api.anthropic.com"
        case .geminiModels, .geminiChat: "generativelanguage.googleapis.com"
        case .groqModels, .groqChat: "api.groq.com"
        }
    }

    var path: String {
        switch self {
        case .openAIModels, .anthropicModels: "/v1/models"
        case .openAIChat: "/v1/chat/completions"
        case .openAIResponses: "/v1/responses"
        case .anthropicMessages: "/v1/messages"
        case .geminiModels: "/v1beta/openai/models"
        case .geminiChat: "/v1beta/openai/chat/completions"
        case .groqModels: "/openai/v1/models"
        case .groqChat: "/openai/v1/chat/completions"
        }
    }

    var requiresBody: Bool {
        switch self {
        case .openAIModels, .anthropicModels, .geminiModels, .groqModels: false
        default: true
        }
    }

    /// Call on a broker worker under its resolution and concurrency limits.
    func destinations(resolving resolve: (String) throws -> [NWEndpoint.Host] = CloudEgressDNS.resolve) throws -> [CloudEgressDestination] {
        let answers = try resolve(hostname + ".")
        guard !answers.isEmpty, answers.count <= CloudEgressDNS.maximumAnswers,
              answers.allSatisfy(CloudEgressAddress.isPublic) else {
            throw CloudEgressError.invalidAddress
        }
        var seen = Set<NWEndpoint.Host>()
        return answers.filter { seen.insert($0).inserted }.map {
            CloudEgressDestination(hostname: hostname, endpoint: .hostPort(host: $0, port: .https))
        }
    }
}

struct CloudEgressRequest: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    static let maximumBodyBytes = 16 * 1024 * 1024
    static let maximumKeyBytes = 4096
    let route: CloudEgressRoute
    let header: Data
    let body: Data

    init(route: CloudEgressRoute, apiKey: String, body: Data = Data(), streaming: Bool = false) throws {
        guard !apiKey.isEmpty, apiKey.utf8.count <= Self.maximumKeyBytes,
              apiKey.utf8.allSatisfy({ (0x21...0x7e).contains($0) }),
              body.count <= Self.maximumBodyBytes, route.requiresBody == !body.isEmpty,
              route.requiresBody || !streaming else {
            throw CloudEgressError.invalidRequest
        }
        self.route = route
        self.body = body

        let method = route.requiresBody ? "POST" : "GET"
        let accept = streaming ? "text/event-stream" : "application/json"
        var lines = [
            "\(method) \(route.path) HTTP/1.1", "Host: \(route.hostname)",
            "Connection: close", "Accept-Encoding: identity", "Accept: \(accept)"
        ]
        switch route {
        case .anthropicModels, .anthropicMessages:
            lines += ["x-api-key: \(apiKey)", "anthropic-version: 2023-06-01"]
        default:
            lines.append("Authorization: Bearer \(apiKey)")
        }
        if route.requiresBody {
            lines += ["Content-Type: application/json", "Content-Length: \(body.count)"]
        }
        header = Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    }

    var description: String { "CloudEgressRequest(\(route.rawValue), <redacted>)" }
    var debugDescription: String { description }
}

struct CloudEgressDestination: Sendable {
    let hostname: String
    let endpoint: NWEndpoint

    fileprivate init(hostname: String, endpoint: NWEndpoint) {
        self.hostname = hostname
        self.endpoint = endpoint
    }

    func verifiesTLS(_ trust: SecTrust) -> Bool {
        let policy = SecPolicyCreateSSL(true, hostname as CFString)
        guard SecTrustSetPolicies(trust, policy) == errSecSuccess,
              SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess else { return false }
        return SecTrustEvaluateWithError(trust, nil)
    }

}

private enum CloudEgressDNS {
    static let maximumAnswers = 32

    static func resolve(_ name: String) throws -> [NWEndpoint.Host] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP
        var head: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(name, nil, &hints, &head) == 0, let head else {
            throw CloudEgressError.resolutionFailed
        }
        defer { freeaddrinfo(head) }
        var results: [NWEndpoint.Host] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = head
        while let node = cursor {
            let entry = node.pointee
            guard results.count < maximumAnswers, let pointer = entry.ai_addr else {
                throw CloudEgressError.invalidAddress
            }
            switch entry.ai_family {
            case AF_INET where entry.ai_addrlen >= MemoryLayout<sockaddr_in>.size:
                let address = pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                guard let ip = IPv4Address(withUnsafeBytes(of: address) { Data($0) }) else { throw CloudEgressError.invalidAddress }
                results.append(.ipv4(ip))
            case AF_INET6 where entry.ai_addrlen >= MemoryLayout<sockaddr_in6>.size:
                let address = pointer.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
                guard address.sin6_scope_id == 0,
                      let ip = IPv6Address(withUnsafeBytes(of: address.sin6_addr) { Data($0) }) else { throw CloudEgressError.invalidAddress }
                results.append(.ipv6(ip))
            default:
                throw CloudEgressError.invalidAddress
            }
            cursor = entry.ai_next
        }
        return results
    }
}

private enum CloudEgressAddress {
    // Deny special-purpose ranges and multicast, including globally reachable
    // exceptions in the IANA special-purpose registries.
    private static let specialV4: [(prefix: UInt32, bits: Int)] = [
        (0x00000000, 8), (0x0a000000, 8), (0x64400000, 10), (0x7f000000, 8),
        (0xa9fe0000, 16), (0xac100000, 12), (0xc0000000, 24), (0xc0000200, 24),
        (0xc01fc400, 24), (0xc034c100, 24), (0xc0586300, 24), (0xc0a80000, 16),
        (0xc0af3000, 24), (0xc6120000, 15), (0xc6336400, 24), (0xcb007100, 24),
        (0xe0000000, 3)
    ]

    static func isPublic(_ host: NWEndpoint.Host) -> Bool {
        guard host.interface == nil else { return false }
        switch host {
        case .ipv4(let ip):
            let value = ip.rawValue.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            return !specialV4.contains { range in
                let mask = UInt32.max << (32 - range.bits)
                return value & mask == range.prefix
            }
        case .ipv6(let ip):
            let bytes = Array(ip.rawValue)
            guard bytes[0] & 0xe0 == 0x20 else { return false }
            let prefix = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            switch prefix {
            case 0x2001: return bytes[2] > 1 && (bytes[2] != 0x0d || bytes[3] != 0xb8)
            case 0x2002: return false
            case 0x2620: return Array(bytes[2..<6]) != [0, 0x4f, 0x80, 0]
            case 0x3fff: return bytes[2] & 0xf0 != 0
            default: return true
            }
        default:
            return false
        }
    }
}
