import Foundation
import XCTest
@testable import ArtexCore

final class GuestCapabilityTests: XCTestCase {
    func testRuntimeGateRequiresAllReadinessConditionsAndCurrentDeclaration() {
        for declared in [false, true] {
            let features = GuestRuntimeFeatures(trafficBlobExportDeclared: declared)
            for state in [LifecycleState.idle, .starting, .running, .stopping, .stopped, .failed] {
                for ready in [false, true] {
                    for machine in [false, true] {
                        XCTAssertEqual(features.allowsTrafficBlobExport(state: state, ready: ready, hasMachine: machine), declared && state == .running && ready && machine)
                    }
                }
            }
        }
        XCTAssertFalse(GuestRuntimeFeatures().allowsTrafficBlobExport(state: .running, ready: true, hasMachine: true))
    }
    @MainActor func testControllerCannotExposeCapabilityBeforeBootOrAfterFailedStart() async {
        let controller = VMController()
        XCTAssertFalse(controller.canExportTrafficBlobs)
        XCTAssertNil(controller.trafficBlobExportGeneration)
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do { try await controller.start(artifacts: missing, logs: missing); XCTFail("Missing profile") } catch { }
        XCTAssertFalse(controller.canExportTrafficBlobs)
        XCTAssertNil(controller.trafficBlobExportGeneration)
        XCTAssertFalse(controller.hasMachine)
    }
    private func profile(capabilities: Any? = nil, rootDisk: Bool = true) throws -> (URL, [String: Any]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("artex-capability-"+UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let bytes = Data([1,2,3]), hash = ArtifactIntegrity.sha256(bytes)
        for name in ["Image", "initramfs", "system.ext4"] { try bytes.write(to: root.appendingPathComponent(name)) }
        var manifest: [String: Any] = ["architecture":"arm64","kernel":"Image","kernelSHA256":hash,"initramfs":"initramfs","initramfsSHA256":hash,"bootMode":rootDisk ? "rootDisk" : "initramfs"]
        if rootDisk { manifest["systemDisk"] = "system.ext4"; manifest["systemDiskSHA256"] = hash }
        if let capabilities { manifest["managedCapabilities"] = capabilities }
        return (root, manifest)
    }
    private func save(_ value: [String: Any], root: URL) throws {
        try JSONSerialization.data(withJSONObject: value).write(to: root.appendingPathComponent("manifest.json"))
    }
    func testOnlyBothKnownCapabilitiesOnRootDiskDeclareOriginalBodyExport() throws {
        let flags = ["traffic-blob-metadata-v1", "regular-source-blob-stream-v1"]
        let cases: [(Any?, Bool, Bool)] = [(nil,true,false),([],true,false),(["unknown"],true,false),([flags[0]],true,false),([flags[1]],true,false),(flags,true,true),(flags+["future"],true,true),(flags,false,false)]
        for (capabilities, disk, expected) in cases {
            let (root, value) = try profile(capabilities: capabilities, rootDisk: disk)
            defer { try? FileManager.default.removeItem(at: root) }
            try save(value, root: root)
            XCTAssertEqual(try GuestArtifacts.load(from: root).declaresTrafficBlobExport, expected)
        }
    }
    func testDeclaredCapabilityCannotBypassFileVerificationOrMalformedManifest() throws {
        let (root, original) = try profile(capabilities: ["traffic-blob-metadata-v1", "regular-source-blob-stream-v1"])
        defer { try? FileManager.default.removeItem(at: root) }
        try save(original, root: root)
        XCTAssertTrue(try GuestArtifacts.load(from: root).declaresTrafficBlobExport)
        try Data([9]).write(to: root.appendingPathComponent("system.ext4"))
        XCTAssertThrowsError(try GuestArtifacts.load(from: root))
        try Data([1,2,3]).write(to: root.appendingPathComponent("system.ext4"))
        let malformedValues: [Any] = [true, "traffic-blob-metadata-v1", [1], ["traffic-blob-metadata-v1", 1]]
        for malformed in malformedValues {
            var value = original; value["managedCapabilities"] = malformed
            try save(value, root: root)
            XCTAssertThrowsError(try GuestArtifacts.load(from: root))
        }
    }
}
