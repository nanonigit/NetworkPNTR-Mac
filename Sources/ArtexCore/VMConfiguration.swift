import Foundation
import Virtualization

public enum VMConfiguration {
    public static func make(kernel: URL, initramfs: URL, input: FileHandle?, output: FileHandle) throws -> VZVirtualMachineConfiguration {
        let configuration = VZVirtualMachineConfiguration()
        configuration.platform = VZGenericPlatformConfiguration()
        configuration.cpuCount = 2
        configuration.memorySize = 512 * 1024 * 1024
        let boot = VZLinuxBootLoader(kernelURL: kernel)
        boot.initialRamdiskURL = initramfs
        boot.commandLine = "console=hvc0 rdinit=/init panic=-1 quiet"
        configuration.bootLoader = boot
        let serial = VZVirtioConsoleDeviceSerialPortConfiguration()
        serial.attachment = VZFileHandleSerialPortAttachment(fileHandleForReading: input, fileHandleForWriting: output)
        configuration.serialPorts = [serial]
        configuration.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
        // Deliberately no NICs, disks, directory shares, sockets or host command bridge.
        configuration.networkDevices = []
        configuration.storageDevices = []
        configuration.directorySharingDevices = []
        configuration.socketDevices = []
        return configuration
    }
}
