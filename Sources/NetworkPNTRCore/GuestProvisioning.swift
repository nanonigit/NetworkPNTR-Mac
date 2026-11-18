import Foundation
import Security

public struct GuestProvisioning: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let transportToken: String
    public let setupToken: String
    public let localSessionCapability: String?

    public init(transportToken: String, setupToken: String, localSessionCapability: String? = nil) throws {
        guard Self.valid(transportToken), Self.valid(setupToken), transportToken != setupToken else {
            throw RuntimeError.integrity("bootstrap credentials")
        }
        if let localSessionCapability {
            guard Self.valid(localSessionCapability), localSessionCapability != transportToken, localSessionCapability != setupToken else {
                throw RuntimeError.integrity("independent local session capability")
            }
        }
        self.localSessionCapability = localSessionCapability
        self.transportToken = transportToken
        self.setupToken = setupToken
    }
    public static func generate(localSession: Bool = false) throws -> Self {
        func token() throws -> String {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                throw RuntimeError.integrity("secure random source")
            }
            return bytes.map { String(format: "%02x", $0) }.joined()
        }
        return try Self(transportToken: token(), setupToken: token(), localSessionCapability: localSession ? token() : nil)
    }
    public var serialBootstrap: String {
        if let localSessionCapability { return "NETWORKPNTR_BOOTSTRAP_2 \(transportToken) \(setupToken) \(localSessionCapability)\n" }
        return "ARTEX_BOOTSTRAP \(transportToken) \(setupToken)\n"
    }
    public var description: String { "GuestProvisioning(<redacted>)" }
    public var debugDescription: String { description }
    private static func valid(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
