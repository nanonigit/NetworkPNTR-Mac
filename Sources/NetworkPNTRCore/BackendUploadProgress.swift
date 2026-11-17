import Foundation

/// Bytes written to the stream, not a server storage acknowledgement.
public struct BackendUploadProgress: Sendable, Equatable {
    public let sentBodyBytes: Int64
    public let totalBodyBytes: Int64
    init(sentBodyBytes: Int64, totalBodyBytes: Int64) {
        self.sentBodyBytes = sentBodyBytes; self.totalBodyBytes = totalBodyBytes
    }
}

/// Runs synchronously on the transfer worker; never block waiting for the main actor.
public typealias BackendUploadProgressHandler = @Sendable (BackendUploadProgress) -> Void

final class BackendUploadProgressReporter {
    private let total: Int64
    private let progress: BackendUploadProgressHandler?
    private var observed: Int64 = 0
    private var delivered: Int64 = 0
    private var last: ContinuousClock.Instant?
    init(totalBodyBytes: Int64, progress: BackendUploadProgressHandler?) throws {
        guard totalBodyBytes > 0 else { throw BackendAPIError.invalidResponse }
        total = totalBodyBytes; self.progress = progress
    }
    func record(sentBodyBytes: Int64, now: ContinuousClock.Instant = .now) throws {
        guard sentBodyBytes >= observed, sentBodyBytes <= total else { throw BackendAPIError.invalidResponse }
        observed = sentBodyBytes
        guard sentBodyBytes > delivered, last == nil || sentBodyBytes == total || last!.duration(to: now) >= .milliseconds(50) else { return }
        delivered = sentBodyBytes; last = now
        progress?(BackendUploadProgress(sentBodyBytes: sentBodyBytes, totalBodyBytes: total))
    }
}

/// Serializes delivery with invalidation. Recursive close permits task cancellation
/// from a callback to synchronously invalidate its own gate without deadlock.
final class BackendUploadProgressGate: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var active = true
    private let callback: BackendUploadProgressHandler
    init(_ callback: @escaping BackendUploadProgressHandler) { self.callback = callback }
    func receive(_ value: BackendUploadProgress) {
        lock.lock(); defer { lock.unlock() }
        if active { callback(value) }
    }
    func close() { lock.lock(); active = false; lock.unlock() }
}
