import Foundation
import XCTest
@testable import NetworkPNTRCore

final class LocalSessionBootstrapTests: XCTestCase {
    func testLegacyBootstrapRemainsByteIdentical() throws {
        let a = String(repeating: "a", count: 64), b = String(repeating: "b", count: 64)
        let provisioning = try GuestProvisioning(transportToken: a, setupToken: b)
        XCTAssertNil(provisioning.localSessionCapability)
        XCTAssertEqual(provisioning.serialBootstrap, "ARTEX_BOOTSTRAP \(a) \(b)\n")
    }

    func testNativeBootstrapUsesIndependentSecretAndRedactsDescriptions() throws {
        let a = String(repeating: "a", count: 64), b = String(repeating: "b", count: 64), c = String(repeating: "c", count: 64)
        let provisioning = try GuestProvisioning(transportToken: a, setupToken: b, localSessionCapability: c)
        XCTAssertEqual(provisioning.serialBootstrap, "NETWORKPNTR_BOOTSTRAP_2 \(a) \(b) \(c)\n")
        XCTAssertFalse(provisioning.description.contains(c))
        XCTAssertFalse(provisioning.debugDescription.contains(c))
        for invalid in [a, b, "short", String(repeating: "G", count: 64), c + "\n"] {
            XCTAssertThrowsError(try GuestProvisioning(transportToken: a, setupToken: b, localSessionCapability: invalid))
        }
        for _ in 0..<8 {
            let generated = try GuestProvisioning.generate(localSession: true)
            let values = [generated.transportToken, generated.setupToken, try XCTUnwrap(generated.localSessionCapability)]
            XCTAssertEqual(Set(values).count, 3)
            XCTAssertTrue(values.allSatisfy { $0.utf8.count == 64 && $0.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } })
        }
    }

    func testNativeBootstrapRequiresDeclaredVerifiedGuestCapability() throws {
        var object: [String: Any] = ["architecture":"arm64", "kernel":"Image", "kernelSHA256":String(repeating:"a",count:64), "initramfs":"initrd", "initramfsSHA256":String(repeating:"b",count:64), "systemDisk":"system.ext4", "systemDiskSHA256":String(repeating:"c",count:64)]
        let native = try GuestProvisioning.generate(localSession: true)
        let legacy = try JSONDecoder().decode(GuestArtifacts.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(legacy.declaresNativeLocalSession)
        XCTAssertThrowsError(try legacy.requireCompatibleBootstrap(native))
        XCTAssertNoThrow(try legacy.requireCompatibleBootstrap(GuestProvisioning.generate()))
        object["managedCapabilities"] = ["native-local-session-v1"]
        let declared = try JSONDecoder().decode(GuestArtifacts.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(declared.declaresNativeLocalSession)
        XCTAssertNoThrow(try declared.requireCompatibleBootstrap(native))
    }
}
