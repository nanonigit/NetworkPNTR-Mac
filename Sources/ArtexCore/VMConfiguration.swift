import Foundation
import Virtualization

public enum VMConfiguration {
    public static func make(kernel: URL, initramfs: URL, input: FileHandle?, output: FileHandle, systemDisk: URL? = nil, dataDisk: URL? = nil) throws -> VZVirtualMachineConfiguration {
        guard (systemDisk == nil) == (dataDisk == nil) else { throw RuntimeError.integrity("paired guest disks") }
        let configuration = VZVirtualMachineConfiguration()
        configuration.platform = VZGenericPlatformConfiguration()
        configuration.cpuCount = 2
        configuration.memorySize = (systemDisk == nil ? 512 : 2048) * 1024 * 1024
        let boot = VZLinuxBootLoader(kernelURL: kernel)
        boot.initialRamdiskURL = initramfs
        boot.commandLine = "console=hvc0 rdinit=/init panic=0 quiet"
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
