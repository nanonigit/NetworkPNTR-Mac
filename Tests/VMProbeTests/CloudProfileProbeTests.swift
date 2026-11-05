import ArtexCore
import Foundation
import XCTest
@testable import VMProbe

@MainActor final class CloudProfileProbeTests: XCTestCase {
    func testCandidateRequiresPinnedCloudBackendAndIsolatedProfile() throws {
        let digest = "94ce92158f608d1b56b2e19a5e8f73e9eb596019f6fc0df96da1bd2891bedb56"
        let metadata: [String: Any] = [
            "architecture": "arm64", "sourceCommit": "e75ae371ad777ffd1eecdd28d2781a6519b05591",
            "bootMode": "rootDisk", "cpuCount": 1, "networkDevices": 0, "hostShares": 0,
            "backendSHA256": digest,
            "managedBackend": ["binarySHA256": digest, "buildVersion": "artex-mac-e75ae371-cloud1"],
            "managedCapabilities": ["traffic-blob-metadata-v1", "regular-source-blob-stream-v1", "cloud-tool-history-v1"]
        ]
        XCTAssertNoThrow(try CloudProfileProbe.validateCandidate(metadata))
        for (key, value): (String, Any) in [
            ("networkDevices", 1), ("hostShares", 1), ("cpuCount", 2), ("bootMode", "initramfs"),
            ("backendSHA256", String(repeating: "a", count: 64)), ("managedCapabilities", ["cloud-tool-history-v1"]),
            ("sourceCommit", "other"), ("managedBackend", ["buildVersion": "artex-mac-e75ae371-blob1", "binarySHA256": digest])
        ] {
            var changed = metadata
            changed[key] = value
            XCTAssertThrowsError(try CloudProfileProbe.validateCandidate(changed), key)
        }
    }

    func testProfileProofRejectsWrongEndpointMissingHintAndExtraRows() throws {
        var ids: [LLMCloudProvider: Int64] = [:]
        var rows: [[String: Any]] = []
        for (offset, provider) in LLMCloudProvider.allCases.enumerated() {
            let id = Int64(offset + 1)
            ids[provider] = id
            let draft = CloudProfileProbe.fixtureDraft(provider)
            var row = try XCTUnwrap(JSONSerialization.jsonObject(with: draft.encoded()) as? [String: Any])
            row.removeValue(forKey: "api_key")
            row["id"] = String(id)
            row["api_key_hint"] = "masked-\(id)"
            row["is_default"] = false
            rows.append(row)
        }
        func decoded(_ rows: [[String: Any]]) throws -> [LLMProfile] {
            try LLMWire.decode([LLMProfile].self, from: JSONSerialization.data(withJSONObject: rows))
        }
        let snapshot = try CloudProfileProbe.snapshot(try decoded(rows), ids: ids)
        XCTAssertEqual(snapshot.rows.count, 4)
        XCTAssertEqual(snapshot.hints.count, 4)
        var wrong = rows
        wrong[2]["base_url"] = "https://custom.invalid/v1"
        XCTAssertThrowsError(try CloudProfileProbe.snapshot(try decoded(wrong), ids: ids))
        wrong = rows
        wrong[2].removeValue(forKey: "api_key_hint")
        XCTAssertThrowsError(try CloudProfileProbe.snapshot(try decoded(wrong), ids: ids))
        XCTAssertThrowsError(try CloudProfileProbe.snapshot(try decoded(rows + [rows[0]]), ids: ids))
        var duplicate = ids
        duplicate[.gemini] = ids[.groq]
        XCTAssertThrowsError(try CloudProfileProbe.snapshot(try decoded(rows), ids: duplicate))
    }
}
