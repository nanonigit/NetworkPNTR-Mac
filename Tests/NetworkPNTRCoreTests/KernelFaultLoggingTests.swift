import XCTest
import Virtualization
@testable import NetworkPNTRCore

final class KernelFaultLoggingTests: XCTestCase {
    func testNormalArgumentsRemainExactForBothBootModes() throws {
        XCTAssertEqual(try VMConfiguration.bootCommandLine(directRoot: true), "console=hvc0 root=/dev/vda rootfstype=ext4 ro rootwait init=/sbin/artex-init panic=0 quiet")
        XCTAssertEqual(try VMConfiguration.bootCommandLine(directRoot: false), "console=hvc0 rdinit=/init panic=0 quiet")
    }

    func testFaultTraceChangesOnlyFixedLoggingArguments() throws {
        #if DEBUG
        for directRoot in [false, true] {
            let ordinary = try VMConfiguration.bootCommandLine(directRoot: directRoot)
            let traced = try VMConfiguration.bootCommandLine(directRoot: directRoot, kernelFaultTracing: true)
            XCTAssertEqual(traced, ordinary.replacingOccurrences(of: " quiet", with: " loglevel=7 print-fatal-signals=1"))
            XCTAssertTrue(traced.contains("panic=0"))
        }
        #else
        XCTAssertThrowsError(try VMConfiguration.bootCommandLine(directRoot: false, kernelFaultTracing: true))
        #endif
    }
    func testTracePreservesHardwareAndIsolation() throws {
        #if DEBUG
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let system = root.appendingPathComponent("system"); let data = root.appendingPathComponent("state")
        _ = try PersistentGuestDisk.createIfMissing(at: system, byteCount: 1024 * 1024)
        _ = try PersistentGuestDisk.createIfMissing(at: data, byteCount: 1024 * 1024)
        for directRoot in [false, true] {
            for cpu in [1, 2] {
                let config = try VMConfiguration.make(kernel: root.appendingPathComponent("Image"), initramfs: root.appendingPathComponent("initrd"), input: nil, output: .standardOutput, systemDisk: system, dataDisk: data, directRoot: directRoot, cpuCount: cpu, kernelFaultTracing: true)
                XCTAssertEqual(config.cpuCount, cpu)
                XCTAssertEqual(config.memorySize, 2048 * 1024 * 1024)
                XCTAssertTrue(config.networkDevices.isEmpty)
                XCTAssertTrue(config.directorySharingDevices.isEmpty)
                XCTAssertEqual(config.storageDevices.count, 2)
                XCTAssertEqual(config.socketDevices.count, 1)
                let boot = try XCTUnwrap(config.bootLoader as? VZLinuxBootLoader)
                XCTAssertEqual(boot.initialRamdiskURL, directRoot ? nil : root.appendingPathComponent("initrd"))
                XCTAssertEqual(boot.commandLine, try VMConfiguration.bootCommandLine(directRoot: directRoot, kernelFaultTracing: true))
            }
        }
        #endif
    }

}
