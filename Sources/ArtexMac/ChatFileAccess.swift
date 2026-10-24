import Foundation

/// Access lasts through the awaited transfer, including its cancellation cleanup.
@MainActor struct ChatFileAccess {
    let start: (URL) -> Bool
    let stop: (URL) -> Void
    init(start: @escaping (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
         stop: @escaping (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }) {
        self.start = start; self.stop = stop
    }
    func withAccess<Value>(_ files: [URL], operation: () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        // An unscoped readable URL can return false; release only successful scopes.
        let scoped = files.filter(start)
        defer { for file in scoped.reversed() { stop(file) } }
        return try await operation()
    }
}
