#if DEBUG
import NetworkPNTRCore
import CryptoKit
import Darwin
import Foundation

struct EvidenceFileProof: Codable, Equatable {
    let body: String
    let byteCount: Int64
    let sha256: String
}

enum EvidenceProbeFile {
    static func observedBytes(_ directory: URL, expectedSize: Int64) throws -> Int64? {
        var info = stat()
        guard expectedSize > 0, lstat(directory.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == getuid() else { throw failure() }
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".artex-evidence-") && $0.hasSuffix(".partial") }
        guard names.count <= 1 else { throw failure() }
        guard let name = names.first else { return nil }
        let stage = directory.appendingPathComponent(name)
        if lstat(stage.path, &info) != 0 {
            if errno == ENOENT { return nil }
            throw failure()
        }
        guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid() else { throw failure() }
        let body = stage.appendingPathComponent("body.partial")
        if lstat(body.path, &info) != 0 {
            if errno == ENOENT { return nil }
            throw failure()
        }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(), info.st_size >= 0, info.st_size <= expectedSize else { throw failure() }
        return info.st_size > 0 && info.st_size < expectedSize ? Int64(info.st_size) : nil
    }
    static func stagingAbsent(_ output: URL) -> Bool {
        for (index, directory) in [output, output.appendingPathComponent("downloads-1"), output.appendingPathComponent("downloads-2")].enumerated() {
            var info = stat()
            if lstat(directory.path, &info) != 0 {
                if index > 0, errno == ENOENT { continue }
                return false
            }
            guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid(),
                  let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path),
                  !names.contains(where: { $0.hasPrefix(".artex-evidence-") }) else { return false }
        }
        return true
    }
    static func verify(_ url: URL, body: String, expected: EvidenceFixtureClient.Body) throws -> EvidenceFileProof {
        var named = stat()
        guard lstat(url.path, &named) == 0, named.st_mode & S_IFMT == S_IFREG else { throw failure() }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw failure() }
        defer { Darwin.close(fd) }
        var before = stat()
        guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_uid == getuid(), before.st_size == expected.size,
              before.st_dev == named.st_dev, before.st_ino == named.st_ino else { throw failure() }
        var hash = SHA256(), count: Int64 = 0, buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            try Task.checkCancellation()
            let length = Darwin.read(fd, &buffer, buffer.count)
            if length < 0, errno == EINTR { continue }
            guard length >= 0, Int64(length) <= expected.size - count else { throw failure() }
            if length == 0 { break }
            hash.update(data: Data(buffer.prefix(length))); count += Int64(length)
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        var after = stat()
        guard fstat(fd, &after) == 0, count == expected.size, digest == expected.sha256,
              before.st_size == after.st_size, before.st_dev == after.st_dev, before.st_ino == after.st_ino,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else { throw failure() }
        return EvidenceFileProof(body: body, byteCount: count, sha256: digest)
    }
    private static func failure() -> RuntimeError { .integrity("evidence probe file proof") }
}
#endif
