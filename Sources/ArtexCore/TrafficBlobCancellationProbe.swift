#if DEBUG
import Foundation

/// Diagnostic controlled-reader pause; a partial file alone is never an interruption witness.
package final class TrafficBlobCancellationProbe: @unchecked Sendable {
    package struct Partial: Sendable, Equatable {
        package let operationID: UUID
        package let bytes: Int64
    }
    package struct Transfer: Sendable {
        package let probe: TrafficBlobCancellationProbe
        package let operationID: UUID
        package let manifest: TrafficBlobDownload
        package init(probe: TrafficBlobCancellationProbe, operationID: UUID, manifest: TrafficBlobDownload) {
            self.probe = probe; self.operationID = operationID; self.manifest = manifest
        }
    }
    @TaskLocal package static var current: Transfer?
    private enum Phase { case fresh, paused, interrupted, invalid }
    private let condition = NSCondition()
    private let expected: TrafficBlobDownload
    private let timeout: TimeInterval
    private let now: @Sendable () -> ContinuousClock.Instant
    private var phase = Phase.fresh
    private var observation: Partial?
    private var deadline: ContinuousClock.Instant?
    package init(expected: TrafficBlobDownload, timeout: TimeInterval = 10, now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }) {
        self.expected = expected; self.timeout = timeout; self.now = now
    }
    private func matches(_ manifest: TrafficBlobDownload) -> Bool {
        manifest.identity == expected.identity && manifest.side == expected.side &&
        manifest.expectedSize == expected.expectedSize && manifest.expectedSHA256 == expected.expectedSHA256
    }
    package func pauseAfterAppend(operationID: UUID, manifest: TrafficBlobDownload, bytes: Int64) throws {
        condition.lock(); defer { condition.unlock() }
        guard phase == .fresh, matches(manifest), bytes > 0, bytes < expected.expectedSize,
              timeout.isFinite, timeout > 0, timeout <= 10 else {
            phase = .invalid; condition.broadcast(); throw failure()
        }
        observation = Partial(operationID: operationID, bytes: bytes); phase = .paused
        let deadline = now().advanced(by: .seconds(timeout))
        self.deadline = deadline
        while phase == .paused {
            guard now() < deadline else { phase = .invalid; break }
            _ = condition.wait(until: Date(timeIntervalSinceNow: min(timeout, 0.05)))
        }
        guard phase == .interrupted else { throw failure() }
        throw CancellationError()
    }
    package func recordCancellation(operationID: UUID, manifest: TrafficBlobDownload, interrupted: Bool) {
        condition.lock(); defer { condition.broadcast(); condition.unlock() }
        guard phase == .paused, let deadline, now() < deadline, matches(manifest), observation?.operationID == operationID, interrupted else {
            phase = .invalid; return
        }
        phase = .interrupted
    }
    package var partial: Partial? {
        condition.lock(); defer { condition.unlock() }
        return phase == .paused ? observation : nil
    }
    package var witness: Partial? {
        condition.lock(); defer { condition.unlock() }
        return phase == .interrupted ? observation : nil
    }
    private func failure() -> RuntimeError { .integrity("controlled source blob interruption") }
}
#endif
