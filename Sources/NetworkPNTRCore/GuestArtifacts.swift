import CryptoKit
import Foundation

public enum ArtifactIntegrity {
    public static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    @discardableResult public static func verify(name: String, expected: String, directory: URL, maximumBytes: Int = 256 * 1024 * 1024) throws -> URL {
        guard !name.isEmpty, name == URL(fileURLWithPath: name).lastPathComponent, !name.contains("/"), !name.contains("\\"), expected.count == 64 else { throw RuntimeError.integrity(name) }
        let url = directory.appendingPathComponent(name)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) > 0, (values.fileSize ?? Int.max) <= maximumBytes else { throw RuntimeError.integrity(name) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { hasher.update(data: chunk) }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == expected else { throw RuntimeError.integrity(name) }
        return url
    }
}
public struct GuestArtifacts: Codable, Sendable {
    public let architecture: String
    public let kernel: String
    public let kernelSHA256: String
    public let initramfs: String
    public let initramfsSHA256: String
    public let bootMode: String?
    public let cpuCount: Int?
    public let systemDisk: String?
    public let systemDiskSHA256: String?
    public let managedCapabilities: [String]?
    public var declaresNativeLocalSession: Bool {
        systemDisk != nil && managedCapabilities?.contains("native-local-session-v1") == true
    }
    func requireCompatibleBootstrap(_ provisioning: GuestProvisioning) throws {
        guard provisioning.localSessionCapability == nil || declaresNativeLocalSession else {
            throw RuntimeError.integrity("native local session guest capability")
        }
    }
    /// Compatibility declaration only; callers must load verified files and bind it to a live VM.
    public var declaresTrafficBlobExport: Bool {
        bootMode == "rootDisk" && systemDisk != nil &&
        managedCapabilities?.contains("traffic-blob-metadata-v1") == true &&
        managedCapabilities?.contains("regular-source-blob-stream-v1") == true
    }
    public static func load(from directory: URL) throws -> GuestArtifacts {
        try load(from: directory, cloudEgress: false)
    }

    static func load(from directory: URL, cloudEgress: Bool) throws -> GuestArtifacts {
        let url = directory.appendingPathComponent("manifest.json")
        let data: Data
        if cloudEgress {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw RuntimeError.integrity("cloud egress manifest file")
            }
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            data = try file.read(upToCount: 64 * 1024 + 1) ?? Data()
            try requireCloudEgressManifest(data)
        } else {
            data = try Data(contentsOf: url)
        }
        let manifest = try JSONDecoder().decode(Self.self, from: data)
        if let mode = manifest.bootMode {
            guard ["initramfs", "rootDisk"].contains(mode), mode != "rootDisk" || manifest.systemDisk != nil else { throw RuntimeError.integrity("guest boot profile") }
        }
        guard [1, 2].contains(manifest.cpuCount ?? 2) else { throw RuntimeError.integrity("guest CPU budget") }
        guard manifest.architecture == "arm64" else { throw RuntimeError.integrity("architecture") }
        _ = try ArtifactIntegrity.verify(name: manifest.kernel, expected: manifest.kernelSHA256, directory: directory)
        _ = try ArtifactIntegrity.verify(name: manifest.initramfs, expected: manifest.initramfsSHA256, directory: directory)
        guard (manifest.systemDisk == nil) == (manifest.systemDiskSHA256 == nil) else {
            throw RuntimeError.integrity("paired system disk manifest")
        }
        if let name = manifest.systemDisk, let hash = manifest.systemDiskSHA256 {
            _ = try ArtifactIntegrity.verify(name: name, expected: hash, directory: directory, maximumBytes: 1024 * 1024 * 1024)
        }
        return manifest
    }

    package static let cloudEgressManifestSHA256 = "42c47caf03c835c974eee569f8be041b234d3f96b7d7931585e410e146f73c70"
    package static let apiReconSkillManifestSHA256 = "fe0053523608ba436f261ff41d142fe2ceca779571958ca1d19aa2ddaa54f332"

    package static let nativeSessionCloudManifestSHA256 = "40718971e50bd73f9ff5b1cf5bdbc03f55db400f1855fb33d3ef9b3a7c4f4057"

    static func requireCloudEgressManifest(_ data: Data) throws {
        guard data.count <= 64 * 1024,
              [cloudEgressManifestSHA256, apiReconSkillManifestSHA256, nativeSessionCloudManifestSHA256].contains(ArtifactIntegrity.sha256(data)) else {
            throw RuntimeError.integrity("cloud egress manifest digest")
        }
    }
}
