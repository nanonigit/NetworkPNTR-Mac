import Darwin
import Foundation

public enum PersistentGuestDisk {
    /// Creates a sparse private disk once; existing guest bytes are never modified.
    @discardableResult public static func createIfMissing(at url: URL, byteCount: Int64) throws -> Bool {
        guard url.isFileURL, byteCount >= 1024 * 1024, byteCount <= 64 * 1024 * 1024 * 1024,
              byteCount % 512 == 0 else { throw RuntimeError.integrity("state disk size") }
        let descriptor = open(url.path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        if descriptor >= 0 {
            defer { close(descriptor) }
            guard ftruncate(descriptor, off_t(byteCount)) == 0 else {
                let code = errno
                unlink(url.path)
                throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
            }
            return true
        }
        guard errno == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let existing = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard existing >= 0 else { throw RuntimeError.integrity("state disk") }
        defer { close(existing) }
        var info = stat()
        guard fstat(existing, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_nlink == 1,
              info.st_mode & 0o777 == 0o600, info.st_size == byteCount else {
            throw RuntimeError.integrity("state disk attributes")
        }
        return false
    }
}
