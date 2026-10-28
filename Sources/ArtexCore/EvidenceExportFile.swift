import CryptoKit
import Darwin
import Foundation

/// A host-approved new filename under one pinned local directory. Never constructed from guest headers.
public final class EvidenceExportDestination: @unchecked Sendable {
    fileprivate let directory: Int32
    fileprivate let name: String
    public init(newFileURL url: URL) throws {
        guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost",
              url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil else { throw EvidenceExportError.invalidDestination }
        let name = url.lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", name.utf8.count <= 255,
              !name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 || $0 == "/" || $0 == "\\" }) else { throw EvidenceExportError.invalidDestination }
        let fd = Darwin.open(url.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw EvidenceExportError.invalidDestination }
        do { try Self.requireAbsent(fd, name) } catch { Darwin.close(fd); throw error }
        directory = fd; self.name = name
    }
    deinit { Darwin.close(directory) }
    fileprivate static func requireAbsent(_ directory: Int32, _ name: String) throws {
        var info = stat()
        if fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0 { throw EvidenceExportError.destinationExists }
        guard errno == ENOENT else { throw EvidenceExportError.storage }
    }
    fileprivate func actualURL() throws -> URL {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let result = path.withUnsafeMutableBufferPointer { fcntl(directory, F_GETPATH, $0.baseAddress!) }
        guard result == 0, let value = String(validatingCString: path) else { throw EvidenceExportError.storage }
        return URL(fileURLWithPath: value, isDirectory: true).appendingPathComponent(name)
    }
}

public struct SavedEvidenceFile: Sendable {
    public let url: URL
    public let byteCount: Int64
    public let sha256: String
    public let stagingCleanupComplete, directorySynced: Bool
}

/// Single-use verified staging receipt; discard never removes a successfully published file.
public final class VerifiedEvidenceFile: @unchecked Sendable {
    private let writer: EvidenceExportWriter
    fileprivate init(writer: EvidenceExportWriter) { self.writer = writer }
    public func commit() throws -> SavedEvidenceFile { try writer.publish() }
    public func discard() throws { try writer.discard() }
}

/// Single writer, bounded chunks, private same-volume staging. Locks also serialize cancellation/commit.
final class EvidenceExportWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let destination: EvidenceExportDestination
    private let request: FindingEvidenceDownload
    private let stageName = ".artex-evidence-" + UUID().uuidString + ".partial"
    private var stage: Int32?
    private var file: Int32?
    private var written: Int64 = 0
    private enum State { case writing, verified, committed, closed }
    private var state = State.writing
    private var verifiedStamp: Stamp?
    private struct Stamp: Equatable {
        let device: dev_t, inode: ino_t, size: off_t
        let modifiedSeconds, modifiedNanos, changedSeconds, changedNanos: Int
        init(_ value: stat) {
            device = value.st_dev; inode = value.st_ino; size = value.st_size
            modifiedSeconds = value.st_mtimespec.tv_sec; modifiedNanos = value.st_mtimespec.tv_nsec
            changedSeconds = value.st_ctimespec.tv_sec; changedNanos = value.st_ctimespec.tv_nsec
        }
    }
    init(destination: EvidenceExportDestination, request: FindingEvidenceDownload) throws {
        self.destination = destination; self.request = request
        guard mkdirat(destination.directory, stageName, 0o700) == 0 else { throw EvidenceExportError.storage }
        let directory = openat(destination.directory, stageName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else {
            if unlinkat(destination.directory, stageName, AT_REMOVEDIR) != 0, errno != ENOENT { throw EvidenceExportError.cleanupRequired }
            throw EvidenceExportError.storage
        }
        stage = directory
        let fd = openat(directory, "body.partial", O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else {
            if !cleanup() { throw EvidenceExportError.cleanupRequired }
            throw EvidenceExportError.storage
        }
        file = fd
    }
    deinit {
        lock.lock(); _ = cleanup()
        if let stage { Darwin.close(stage) }
        lock.unlock()
    }
    func append(_ bytes: Data) throws {
        lock.lock(); defer { lock.unlock() }
        do {
            try Task.checkCancellation()
            guard state == .writing, let file, bytes.count <= 65536, Int64(bytes.count) <= request.expectedSize - written else { throw EvidenceExportError.integrity }
            try bytes.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    try Task.checkCancellation()
                    let count = Darwin.write(file, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                    if count < 0, errno == EINTR { continue }
                    guard count > 0 else { throw EvidenceExportError.storage }
                    offset += count
                }
            }
            written += Int64(bytes.count)
        } catch { try abort(error) }
    }
    func finish(response: BackendDownloadResult, validate: @Sendable () throws -> Void = {}) throws -> VerifiedEvidenceFile {
        lock.lock(); defer { lock.unlock() }
        do {
            try Task.checkCancellation(); try validate()
            guard state == .writing, let file, response.status == 200, written == request.expectedSize,
                  response.byteCount == written, response.sha256 == request.expectedSHA256,
                  fsync(file) == 0 else { throw EvidenceExportError.integrity }
            var info = stat()
            guard fstat(file, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size == written,
                  lseek(file, 0, SEEK_SET) == 0 else { throw EvidenceExportError.storage }
            let before = Stamp(info)
            var hash = SHA256(), count: Int64 = 0, buffer = [UInt8](repeating: 0, count: 65536)
            while count < written {
                try Task.checkCancellation(); try validate()
                let n = Darwin.read(file, &buffer, min(buffer.count, Int(written - count)))
                if n < 0, errno == EINTR { continue }
                guard n > 0 else { throw EvidenceExportError.integrity }
                hash.update(data: Data(buffer.prefix(n))); count += Int64(n)
            }
            let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
            guard count == written, digest == request.expectedSHA256, fstat(file, &info) == 0, Stamp(info) == before else { throw EvidenceExportError.integrity }
            verifiedStamp = before; state = .verified
            return VerifiedEvidenceFile(writer: self)
        } catch { try abort(error) }
    }
    fileprivate func publish() throws -> SavedEvidenceFile {
        lock.lock(); defer { lock.unlock() }
        do {
            try Task.checkCancellation()
            guard state == .verified, let file, let stage, let verifiedStamp else { throw EvidenceExportError.integrity }
            var info = stat(), named = stat()
            guard fstat(file, &info) == 0, Stamp(info) == verifiedStamp,
                  fstatat(stage, "body.partial", &named, AT_SYMLINK_NOFOLLOW) == 0,
                  named.st_mode & S_IFMT == S_IFREG, named.st_dev == info.st_dev, named.st_ino == info.st_ino else { throw EvidenceExportError.integrity }
            try EvidenceExportDestination.requireAbsent(destination.directory, destination.name)
            let url = try destination.actualURL()
            try Task.checkCancellation()
            guard renameatx_np(stage, "body.partial", destination.directory, destination.name, UInt32(RENAME_EXCL)) == 0 else {
                if errno == EEXIST { throw EvidenceExportError.destinationExists }
                throw EvidenceExportError.storage
            }
            state = .committed
            let cleaned = cleanup(), synced = fsync(destination.directory) == 0
            return SavedEvidenceFile(url: url, byteCount: written, sha256: request.expectedSHA256, stagingCleanupComplete: cleaned, directorySynced: synced)
        } catch { try abort(error) }
    }
    func discard() throws {
        lock.lock(); defer { lock.unlock() }
        if state != .committed { state = .closed }
        guard cleanup() else { throw EvidenceExportError.cleanupRequired }
    }
    private func abort(_ error: any Error) throws -> Never {
        if state != .committed { state = .closed }
        guard cleanup() else { throw EvidenceExportError.cleanupRequired }
        throw error
    }
    /// Never recursively removes unexpected content. On failure explicit callers receive a cleanup error.
    private func cleanup() -> Bool {
        if let file { Darwin.close(file); self.file = nil }
        if let stage {
            if unlinkat(stage, "body.partial", 0) != 0, errno != ENOENT { return false }
            if unlinkat(destination.directory, stageName, AT_REMOVEDIR) != 0, errno != ENOENT { return false }
            Darwin.close(stage); self.stage = nil
        }
        return true
    }
}
