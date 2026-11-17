import NetworkPNTRCore
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
        let manifest = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
        let manifestDigest = ArtifactIntegrity.sha256(manifest)
        XCTAssertNoThrow(try CloudProfileProbe.validateManifest(manifest, expectedSHA256: manifestDigest))
        var changedSystem = metadata
        changedSystem["systemDiskSHA256"] = String(repeating: "b", count: 64)
        let alteredManifest = try JSONSerialization.data(withJSONObject: changedSystem, options: [.sortedKeys])
        XCTAssertThrowsError(try CloudProfileProbe.validateManifest(alteredManifest, expectedSHA256: manifestDigest))

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
        var expectedHints: [LLMCloudProvider: String] = [:]
        for (offset, provider) in LLMCloudProvider.allCases.enumerated() {
            let id = Int64(offset + 1)
            ids[provider] = id
            let draft = CloudProfileProbe.fixtureDraft(provider)
            var row = try XCTUnwrap(JSONSerialization.jsonObject(with: draft.encoded()) as? [String: Any])
            row.removeValue(forKey: "api_key")
            row["id"] = String(id)
            let hint = "…000\(id)"
            expectedHints[provider] = hint
            row["api_key_hint"] = hint
            row["is_default"] = false
            rows.append(row)
        }
        func decoded(_ rows: [[String: Any]]) throws -> [LLMProfile] {
            try LLMWire.decode([LLMProfile].self, from: JSONSerialization.data(withJSONObject: rows))
        }
        let snapshot = try CloudProfileProbe.snapshot(try decoded(rows), ids: ids, expectedHints: expectedHints)
        XCTAssertEqual(snapshot.rows.count, 4)
        XCTAssertEqual(snapshot.hints.count, 4)
        XCTAssertThrowsError(try CloudProfileProbe.snapshot(try decoded(rows), ids: ids, expectedHints: expectedHints, geminiEdited: true))
        var edited = rows
        edited[2]["name"] = "Fixture gemini edited"
        let updated = try CloudProfileProbe.snapshot(try decoded(edited), ids: ids, expectedHints: expectedHints, geminiEdited: true)
        XCTAssertEqual(updated.hints, snapshot.hints)
        XCTAssertNotEqual(updated.rows, snapshot.rows)
        edited[2]["api_key_hint"] = "…xxxx"
        XCTAssertThrowsError(try CloudProfileProbe.snapshot(try decoded(edited), ids: ids, expectedHints: expectedHints, geminiEdited: true))

        var wrong = rows
        wrong[2]["base_url"] = "https://custom.invalid/v1"
        XCTAssertThrowsError(try CloudProfileProbe.snapshot(try decoded(wrong), ids: ids, expectedHints: expectedHints))
        wrong = rows
        wrong[2].removeValue(forKey: "api_key_hint")
        XCTAssertThrowsError(try CloudProfileProbe.snapshot(try decoded(wrong), ids: ids, expectedHints: expectedHints))
        XCTAssertThrowsError(try CloudProfileProbe.snapshot(try decoded(rows + [rows[0]]), ids: ids, expectedHints: expectedHints))
        var duplicate = ids
        duplicate[.gemini] = ids[.groq]
        XCTAssertThrowsError(try CloudProfileProbe.snapshot(try decoded(rows), ids: duplicate, expectedHints: expectedHints))
    }
}
