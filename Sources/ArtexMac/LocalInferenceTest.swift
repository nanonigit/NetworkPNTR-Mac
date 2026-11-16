import ArtexCore
import Foundation
import Observation

/// Consumes explicit test requests once across SwiftUI task restarts.
@MainActor @Observable final class LocalInferenceTest {
    private(set) var requestID = 0
    private(set) var isRunning = false
    private(set) var metrics: OllamaInferenceMetrics?
    private(set) var failure: Error?
    private var startedID = 0

    func request() {
        guard !isRunning else { return }
        requestID += 1
    }

    @discardableResult
    func runPending(
        operation: () async throws -> OllamaTextReply
    ) async -> Bool {
        guard requestID > startedID, !Task.isCancelled else { return false }
        let current = requestID
        startedID = current
        isRunning = true
        metrics = nil
        failure = nil
        defer {
            if requestID == current { isRunning = false }
        }
        do {
            try Task.checkCancellation()
            guard requestID == current else { return false }
            let reply = try await operation()
            try Task.checkCancellation()
            guard requestID == current else { return false }
            metrics = reply.metrics
            return true
        } catch {
            if !Task.isCancelled, requestID == current { failure = error }
            return false
        }
    }
}
