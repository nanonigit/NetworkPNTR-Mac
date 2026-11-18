import Foundation
import XCTest
@testable import NetworkPNTRCore

final class SkillOverrideManifestTests: XCTestCase {
    func testReviewedSkillGuestManifestIsAcceptedAndTamperingRejected() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "api-recon-skill-manifest", withExtension: "json", subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url)
        XCTAssertEqual(ArtifactIntegrity.sha256(data), GuestArtifacts.apiReconSkillManifestSHA256)
        XCTAssertNoThrow(try GuestArtifacts.requireCloudEgressManifest(data))
        var manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        manifest["skillOverrides"] = ["api-recon": ["file": "api-recon/SKILL.md", "sha256": String(repeating: "0", count: 64)]]
        XCTAssertThrowsError(try GuestArtifacts.requireCloudEgressManifest(JSONSerialization.data(withJSONObject: manifest)))
        XCTAssertThrowsError(try GuestArtifacts.requireCloudEgressManifest(data + Data(" ".utf8)))
    }
    func testNativeSessionCompositeIdentityMatchesReviewedCloudManifest() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("evidence/local-session/cloud-composite-manifest.json"))
        XCTAssertEqual(ArtifactIntegrity.sha256(data), GuestArtifacts.nativeSessionCloudCompositeManifestSHA256)
        XCTAssertNoThrow(try GuestArtifacts.requireCloudEgressManifest(data))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let composite = try XCTUnwrap(manifest["managedBackend"] as? [String: Any])
        let parent = try XCTUnwrap(manifest["nativeSessionParentManagedBackend"] as? [String: Any])
        XCTAssertEqual(composite["binarySHA256"] as? String, manifest["backendSHA256"] as? String)
        XCTAssertEqual(composite["buildVersion"] as? String, "dev")
        XCTAssertNotEqual(composite["binarySHA256"] as? String, parent["binarySHA256"] as? String)
        XCTAssertEqual(manifest["sourceCommit"] as? String, "e75ae371ad777ffd1eecdd28d2781a6519b05591")
        XCTAssertThrowsError(try GuestArtifacts.requireCloudEgressManifest(data + Data(" ".utf8)))
    }

}
