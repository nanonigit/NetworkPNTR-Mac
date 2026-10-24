#if DEBUG
import ArtexCore
import Foundation

/// A bounded first-event signal and counters, with no per-chunk main-actor queue.
private final class UploadInterruptionObservation: @unchecked Sendable {
    let events: AsyncStream<BackendUploadProgress>
    private let continuation: AsyncStream<BackendUploadProgress>.Continuation
    private let lock = NSLock()
    private var first: BackendUploadProgress?
    private var last: BackendUploadProgress?
    private var count = 0
    private var valid = true
    private var signalled = false
    private var completed = false
    private var failureKind = "none"
    init() {
        let channel = AsyncStream<BackendUploadProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
        events = channel.stream; continuation = channel.continuation
    }
    func receive(_ event: BackendUploadProgress) {
        lock.lock()
        let initial = first == nil
        if let last, event.totalBodyBytes != last.totalBodyBytes || event.sentBodyBytes <= last.sentBodyBytes { valid = false }
        if initial { first = event }
        last = event; count += 1
        let signal = !signalled && event.sentBodyBytes >= 1024 * 1024
        if signal { signalled = true }
        lock.unlock()
        if signal { continuation.yield(event); continuation.finish() }
    }
    func finish() { continuation.finish() }
    static func classify(_ error: Error) -> String {
        if error is CancellationError { return "cancellation" }
        if case BackendAPIError.status = error { return "http_status" }
        return "transport_or_validation"
    }
    func complete(error: Error? = nil) {
        lock.lock(); completed = true; failureKind = error.map { Self.classify($0) } ?? "success"; lock.unlock()
        continuation.finish()
    }
    func partialRecord(expected: Int64, requireInFlight: Bool = false) throws -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        guard !requireInFlight || !completed else { throw RuntimeError.integrity("transfer finished before interruption: " + failureKind) }
        guard valid, let first, let last, first.sentBodyBytes > 0,
              first.sentBodyBytes <= last.sentBodyBytes, last.sentBodyBytes >= 1024 * 1024, last.sentBodyBytes < expected,
              first.totalBodyBytes == expected, last.totalBodyBytes == expected else { throw RuntimeError.integrity("observed partial attachment transfer") }
        return ["first_body_bytes":first.sentBodyBytes, "last_body_bytes":last.sentBodyBytes,
                "total_body_bytes":expected, "progress_event_count":count, "partial_body_observed":true]
    }
}

/// Runs only after NativeDiagnostics proves fresh test-owned guest authentication.
@MainActor enum NativeUploadCancellationDiagnostics {
    static func run(session: AuthenticationSession, directory: URL,
                    stopAndRestart: @MainActor () async throws -> AuthenticationSession) async throws -> AuthenticationSession {
        let files = directory.appendingPathComponent("upload-cancellation-selected", isDirectory: true)
        guard !FileManager.default.fileExists(atPath: files.path) else { throw RuntimeError.integrity("fresh interruption fixture") }
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: false, attributes: [.posixPermissions:0o700])
        defer { try? FileManager.default.removeItem(at: files) }
        let file = files.appendingPathComponent("interrupt.bin")
        guard FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions:0o600]) else { throw RuntimeError.integrity("interruption selected file") }
        let overhead = try ChatMultipartPlan(files: [file]).contentLength
        let writer = try FileHandle(forWritingTo: file)
        defer { try? writer.close() }
        try writer.truncate(atOffset: UInt64(ChatMultipartBody.maximumBytes - overhead))
        let total = try ChatMultipartPlan(files: [file]).contentLength
        guard total == ChatMultipartBody.maximumBytes else { throw RuntimeError.integrity("interruption fixture body bound") }
        var current = session
        var owned: Int64?
        var pending: Task<BackendHTTPResponse, Error>?
        let cancelled = UploadInterruptionObservation(), stopped = UploadInterruptionObservation()
        defer { cancelled.finish(); stopped.finish() }
        do {
            let conversation = try await ChatService(client: AuthenticatedBackendClient(session: current)).create(agentKey: "auto", title: "Native transfer interruption fixture")
            owned = conversation.id
            let cancelUpload = Task {
                do {
                    let response = try await session.authenticatedUpload(conversationID: conversation.id, files: [file], progress: { cancelled.receive($0) })
                    cancelled.complete(); return response
                } catch { cancelled.complete(error: error); throw error }
            }
            pending = cancelUpload
            _ = try await firstProgress(cancelled)
            _ = try cancelled.partialRecord(expected: total, requireInFlight: true)
            cancelUpload.cancel()
            do {
                _ = try await cancelUpload.value
                throw RuntimeError.integrity("cancelled upload returned success")
            } catch is CancellationError { }
            pending = nil
            var cancelRecord = try cancelled.partialRecord(expected: total)
            try await verifyNoAttachments(conversation.id, session: current)
            cancelRecord["task_cancellation_error"] = true
            cancelRecord["backend_usable_after_cancel"] = true
            cancelRecord["no_persisted_attachment"] = true

            let active = current
            let stopUpload = Task {
                do {
                    let response = try await active.authenticatedUpload(conversationID: conversation.id, files: [file], progress: { stopped.receive($0) })
                    stopped.complete(); return response
                } catch { stopped.complete(error: error); throw error }
            }
            pending = stopUpload
            _ = try await firstProgress(stopped)
            _ = try stopped.partialRecord(expected: total, requireInFlight: true)
            current = try await stopAndRestart()
            guard current.phase == .authenticated else { throw RuntimeError.integrity("interruption restart authentication") }
            let stopResult = await stopUpload.result
            pending = nil
            switch stopResult {
            case .success: throw RuntimeError.integrity("stopped upload returned success")
            case let .failure(error):
                guard error is CancellationError else { throw RuntimeError.integrity("stop transfer failure: " + UploadInterruptionObservation.classify(error)) }
            }
            var stopRecord = try stopped.partialRecord(expected: total)
            try await verifyNoAttachments(conversation.id, session: current)
            stopRecord["transfer_failed"] = true
            stopRecord["transfer_failure_kind"] = "cancellation"
            stopRecord["in_flight_before_stop"] = true
            stopRecord["restarted_authenticated"] = true
            stopRecord["no_persisted_attachment"] = true
            try await cleanup(conversation.id, session: current); owned = nil
            try FileManager.default.removeItem(at: files)
            let report: [String: Any] = ["task_cancel":cancelRecord, "vm_stop":stopRecord,
                "owned_files_and_conversation_cleaned":true, "ui_cancellation_controls":"pending"]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]).write(to: directory.appendingPathComponent("upload-cancellation-vm.json"))
            return current
        } catch {
            if let pending { pending.cancel(); _ = await pending.result }
            if let owned {
                do { try await cleanup(owned, session: current) }
                catch { throw RuntimeError.integrity("interruption fixture cleanup failed") }
            }
            throw error
        }
    }
    private static func firstProgress(_ observation: UploadInterruptionObservation) async throws -> BackendUploadProgress {
        try await withThrowingTaskGroup(of: BackendUploadProgress.self) { group in
            group.addTask {
                for await value in observation.events { return value }
                throw RuntimeError.integrity("missing interruption progress")
            }
            group.addTask { try await Task.sleep(for: .seconds(15)); throw RuntimeError.timeout("interruption progress") }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw RuntimeError.integrity("missing interruption progress") }
            return first
        }
    }
    private struct Listing: Decodable { let entries: [Entry] }
    private struct Entry: Decodable { let name: String }
    private static func workspace(_ id: Int64, operation: String) -> String {
        var query = URLComponents()
        query.queryItems = [URLQueryItem(name: "path", value: "sessions/conv-\(id)/uploads")]
        return "/api/workspace/" + operation + "?" + (query.percentEncodedQuery ?? "")
    }
    private static func verifyNoAttachments(_ id: Int64, session: AuthenticationSession) async throws {
        let response = try await session.authenticatedRequest(method: "GET", path: workspace(id, operation: "list"))
        if response.status == 404 { return }
        guard response.status == 200,
              try BackendJSONCoding.decode(Listing.self, from: response.body).entries.isEmpty else { throw RuntimeError.integrity("interrupted upload left an attachment") }
    }
    private static func cleanup(_ id: Int64, session: AuthenticationSession) async throws {
        let response = try await session.authenticatedRequest(method: "DELETE", path: workspace(id, operation: "delete"))
        guard [200,404].contains(response.status) else { throw RuntimeError.integrity("interruption file cleanup") }
        try await ChatService(client: AuthenticatedBackendClient(session: session)).delete(id: id)
    }
}
#endif
