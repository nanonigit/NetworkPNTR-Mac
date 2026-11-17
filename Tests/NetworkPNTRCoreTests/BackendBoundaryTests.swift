import XCTest
import Virtualization
@testable import NetworkPNTRCore

final class BackendBoundaryTests: XCTestCase {
    func testDiskCreationPreservesExistingDataAndRejectsMismatchOrLinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = root.appendingPathComponent("state.ext4")
        XCTAssertTrue(try PersistentGuestDisk.createIfMissing(at: disk, byteCount: 1024 * 1024))
        let handle = try FileHandle(forWritingTo: disk)
        try handle.write(contentsOf: Data("preserve-me".utf8)); try handle.close()
        XCTAssertFalse(try PersistentGuestDisk.createIfMissing(at: disk, byteCount: 1024 * 1024))
        XCTAssertThrowsError(try PersistentGuestDisk.createIfMissing(at: disk, byteCount: 2 * 1024 * 1024))
        XCTAssertTrue(try Data(contentsOf: disk).starts(with: Data("preserve-me".utf8)))
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: disk)
        XCTAssertThrowsError(try PersistentGuestDisk.createIfMissing(at: link, byteCount: 1024 * 1024))
        let mode = try FileManager.default.attributesOfItem(atPath: disk.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
    }
    func testProvisioningRejectsProtocolInjectionAndRedactsSecrets() throws {
        let secret = String(repeating: "a", count: 64)
        let other = String(repeating: "b", count: 64)
        let provisioning = try GuestProvisioning(transportToken: secret, setupToken: other)
        XCTAssertFalse(String(describing: provisioning).contains(secret))
        XCTAssertFalse(String(reflecting: provisioning).contains(other))
        XCTAssertEqual(provisioning.serialBootstrap, "ARTEX_BOOTSTRAP " + secret + " " + other + "\n")
        XCTAssertThrowsError(try GuestProvisioning(transportToken: secret + "\n", setupToken: other))
        XCTAssertThrowsError(try GuestProvisioning(transportToken: "short", setupToken: other))
    }
    func testBackendVMHasOnlyTwoDisksAndOneVsockWithoutNetworkOrShares() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let system = root.appendingPathComponent("system.ext4")
        let state = root.appendingPathComponent("state.ext4")
        _ = try PersistentGuestDisk.createIfMissing(at: system, byteCount: 1024 * 1024)
        _ = try PersistentGuestDisk.createIfMissing(at: state, byteCount: 1024 * 1024)
        let config = try VMConfiguration.make(kernel: root.appendingPathComponent("Image"), initramfs: root.appendingPathComponent("initramfs"), input: nil, output: .standardOutput, systemDisk: system, dataDisk: state)
        XCTAssertEqual(config.storageDevices.count, 2)
        XCTAssertEqual(config.socketDevices.count, 1)
        let systemAttachment = (config.storageDevices[0] as? VZVirtioBlockDeviceConfiguration)?.attachment as? VZDiskImageStorageDeviceAttachment
        let stateAttachment = (config.storageDevices[1] as? VZVirtioBlockDeviceConfiguration)?.attachment as? VZDiskImageStorageDeviceAttachment
        XCTAssertEqual(systemAttachment?.isReadOnly, true)
        XCTAssertEqual(stateAttachment?.isReadOnly, false)
        XCTAssertEqual(config.networkDevices.count, 0)
        XCTAssertEqual(config.directorySharingDevices.count, 0)
        XCTAssertThrowsError(try VMConfiguration.make(kernel: root.appendingPathComponent("Image"), initramfs: root.appendingPathComponent("initramfs"), input: nil, output: .standardOutput, systemDisk: system))
    }
    func testBackendManifestRejectsPartialAndTamperedSystemDisk() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data("fixture".utf8)
        let digest = ArtifactIntegrity.sha256(bytes)
        for name in ["Image", "initramfs", "system.ext4"] { try bytes.write(to: root.appendingPathComponent(name)) }
        var manifest: [String: Any] = ["architecture": "arm64", "kernel": "Image", "kernelSHA256": digest, "initramfs": "initramfs", "initramfsSHA256": digest, "systemDisk": "system.ext4"]
        func save() throws { try JSONSerialization.data(withJSONObject: manifest).write(to: root.appendingPathComponent("manifest.json")) }
        try save()
        XCTAssertThrowsError(try GuestArtifacts.load(from: root))
        manifest["systemDiskSHA256"] = digest
        try save()
        XCTAssertNoThrow(try GuestArtifacts.load(from: root))
        manifest["bootMode"] = "unsupported"
        try save()
        XCTAssertThrowsError(try GuestArtifacts.load(from: root))
        manifest["bootMode"] = "rootDisk"
        try save()
        XCTAssertNoThrow(try GuestArtifacts.load(from: root))
        manifest["cpuCount"] = 0
        try save()
        XCTAssertThrowsError(try GuestArtifacts.load(from: root))
        manifest["cpuCount"] = 1
        try save()
        XCTAssertNoThrow(try GuestArtifacts.load(from: root))
        try Data("tampered".utf8).write(to: root.appendingPathComponent("system.ext4"))
        XCTAssertThrowsError(try GuestArtifacts.load(from: root))
    }

}
