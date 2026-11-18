import Foundation
import Virtualization

public enum VMConfiguration {
    public static func bootCommandLine(directRoot: Bool, kernelFaultTracing: Bool = false) throws -> String {
        #if !DEBUG
        guard !kernelFaultTracing else { throw RuntimeError.integrity("debug-only kernel fault tracing") }
        #endif
        let root = directRoot ? "root=/dev/vda rootfstype=ext4 ro rootwait init=/sbin/artex-init" : "rdinit=/init"
        let logging = kernelFaultTracing ? "loglevel=7 print-fatal-signals=1" : "quiet"
        return "console=hvc0 \(root) panic=0 \(logging)"
    }

    public static func make(kernel: URL, initramfs: URL, input: FileHandle?, output: FileHandle, systemDisk: URL? = nil, dataDisk: URL? = nil, directRoot: Bool = false, cpuCount: Int = 2, kernelFaultTracing: Bool = false) throws -> VZVirtualMachineConfiguration {
        let commandLine = try bootCommandLine(directRoot: directRoot, kernelFaultTracing: kernelFaultTracing)
        guard (systemDisk == nil) == (dataDisk == nil) else { throw RuntimeError.integrity("paired guest disks") }
        guard !directRoot || systemDisk != nil else { throw RuntimeError.integrity("direct-root system disk") }
        guard [1, 2].contains(cpuCount) else { throw RuntimeError.integrity("guest CPU budget") }
        let configuration = VZVirtualMachineConfiguration()
        configuration.platform = VZGenericPlatformConfiguration()
        configuration.cpuCount = cpuCount
        configuration.memorySize = (systemDisk == nil ? 512 : 2048) * 1024 * 1024
        let boot = VZLinuxBootLoader(kernelURL: kernel)
        boot.initialRamdiskURL = directRoot ? nil : initramfs
        boot.commandLine = commandLine
        configuration.bootLoader = boot
        let serial = VZVirtioConsoleDeviceSerialPortConfiguration()
        serial.attachment = VZFileHandleSerialPortAttachment(fileHandleForReading: input, fileHandleForWriting: output)
        configuration.serialPorts = [serial]
        configuration.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
        // Guests have no NICs, host directory shares or host command bridge.
        configuration.networkDevices = []
        configuration.storageDevices = []
        configuration.directorySharingDevices = []
        configuration.socketDevices = []
        if let systemDisk, let dataDisk {
            guard systemDisk.standardizedFileURL != dataDisk.standardizedFileURL else {
                throw RuntimeError.integrity("distinct guest disks")
            }
            let system = VZVirtioBlockDeviceConfiguration(attachment: try VZDiskImageStorageDeviceAttachment(url: systemDisk, readOnly: true))
            let data = VZVirtioBlockDeviceConfiguration(attachment: try VZDiskImageStorageDeviceAttachment(url: dataDisk, readOnly: false))
            configuration.storageDevices = [system, data]
            configuration.socketDevices = [VZVirtioSocketDeviceConfiguration()]
        }
        return configuration
    }
}
