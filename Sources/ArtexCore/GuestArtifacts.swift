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
    public let systemDisk: String?
    public let systemDiskSHA256: String?
    public static func load(from directory: URL) throws -> GuestArtifacts {
        let manifest = try JSONDecoder().decode(Self.self, from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
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
}
