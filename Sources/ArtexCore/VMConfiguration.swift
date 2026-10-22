import Foundation
import Virtualization

public enum VMConfiguration {
    public static func make(kernel: URL, initramfs: URL, input: FileHandle?, output: FileHandle, systemDisk: URL? = nil, dataDisk: URL? = nil, directRoot: Bool = false, cpuCount: Int = 2) throws -> VZVirtualMachineConfiguration {
        guard (systemDisk == nil) == (dataDisk == nil) else { throw RuntimeError.integrity("paired guest disks") }
        guard !directRoot || systemDisk != nil else { throw RuntimeError.integrity("direct-root system disk") }
        guard [1, 2].contains(cpuCount) else { throw RuntimeError.integrity("guest CPU budget") }
        let configuration = VZVirtualMachineConfiguration()
        configuration.platform = VZGenericPlatformConfiguration()
        configuration.cpuCount = cpuCount
        configuration.memorySize = (systemDisk == nil ? 512 : 2048) * 1024 * 1024
        let boot = VZLinuxBootLoader(kernelURL: kernel)
        boot.initialRamdiskURL = directRoot ? nil : initramfs
        boot.commandLine = directRoot ? "console=hvc0 root=/dev/vda rootfstype=ext4 ro rootwait init=/sbin/artex-init panic=0 quiet" : "console=hvc0 rdinit=/init panic=0 quiet"
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
