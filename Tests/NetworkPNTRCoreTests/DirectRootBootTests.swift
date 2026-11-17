import XCTest
import Virtualization
@testable import NetworkPNTRCore

final class DirectRootBootTests: XCTestCase {
    func testDirectRootRequiresDisksAndDoesNotAttachAnInitramfs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let system = root.appendingPathComponent("system"); let data = root.appendingPathComponent("state")
        _ = try PersistentGuestDisk.createIfMissing(at: system, byteCount: 1024 * 1024)
        _ = try PersistentGuestDisk.createIfMissing(at: data, byteCount: 1024 * 1024)
        let config = try VMConfiguration.make(kernel: root.appendingPathComponent("Image"), initramfs: root.appendingPathComponent("initrd"), input: nil, output: .standardOutput, systemDisk: system, dataDisk: data, directRoot: true)
        let loader = try XCTUnwrap(config.bootLoader as? VZLinuxBootLoader)
        XCTAssertNil(loader.initialRamdiskURL)
        XCTAssertTrue(loader.commandLine.contains("root=/dev/vda"))
        XCTAssertTrue(loader.commandLine.contains("init=/sbin/artex-init"))
        let single = try VMConfiguration.make(kernel: root.appendingPathComponent("Image"), initramfs: root.appendingPathComponent("initrd"), input: nil, output: .standardOutput, systemDisk: system, dataDisk: data, directRoot: true, cpuCount: 1)
        XCTAssertEqual(single.cpuCount, 1)
        for count in [0, 3] {
            XCTAssertThrowsError(try VMConfiguration.make(kernel: root.appendingPathComponent("Image"), initramfs: root.appendingPathComponent("initrd"), input: nil, output: .standardOutput, systemDisk: system, dataDisk: data, directRoot: true, cpuCount: count))
        }
        XCTAssertThrowsError(try VMConfiguration.make(kernel: root.appendingPathComponent("Image"), initramfs: root.appendingPathComponent("initrd"), input: nil, output: .standardOutput, directRoot: true))
    }
}
