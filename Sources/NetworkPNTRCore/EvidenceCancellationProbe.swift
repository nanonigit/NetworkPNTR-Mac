#if DEBUG
import Foundation

/// Developer-only proof for one request; observing a partial file alone cannot prove interruption.
package final class EvidenceCancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let expected: FindingEvidenceDownload
    private var recorded = false
    private var invalid = false
    private var operation: UUID?
    package init(expected: FindingEvidenceDownload) { self.expected = expected }
    package func record(operationID: UUID, manifest: FindingEvidenceDownload, interrupted: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard !recorded else { invalid = true; operation = nil; return }
        recorded = true
        guard manifest.findingID == expected.findingID, manifest.bindingID == expected.bindingID,
              manifest.side == expected.side, manifest.contextTaskID == expected.contextTaskID,
              manifest.expectedSize == expected.expectedSize, manifest.expectedSHA256 == expected.expectedSHA256,
              interrupted else { invalid = true; return }
        operation = operationID
    }
    package var interruptedOperationID: UUID? {
        lock.lock(); defer { lock.unlock() }
        return !invalid && recorded ? operation : nil
    }
}
#endif
