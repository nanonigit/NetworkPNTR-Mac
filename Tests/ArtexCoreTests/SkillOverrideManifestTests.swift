import Foundation
import XCTest
@testable import ArtexCore

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
}
