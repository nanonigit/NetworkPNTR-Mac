import NetworkPNTRCore
import Foundation

/// Access lasts through the awaited transfer, including its cancellation cleanup.
@MainActor struct ChatFileAccess {
    let start: (URL) -> Bool
    let stop: (URL) -> Void
    init(start: @escaping (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
         stop: @escaping (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }) {
        self.start = start; self.stop = stop
    }
    func withAccess<Value>(_ files: [URL], operation: @MainActor () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        // An unscoped readable URL can return false; release only successful scopes.
        let scoped = files.filter(start)
        defer { for file in scoped.reversed() { stop(file) } }
        return try await operation()
    }
}

/// Selection is checked when the scheduled task actually starts, not only on click.
@MainActor enum ChatAttachmentSelection {
    static func upload(_ files: [URL], owner: Int64?, workspace: ChatWorkspace,
                       access: ChatFileAccess = ChatFileAccess()) async throws -> Bool {
        guard !files.isEmpty, !Task.isCancelled, owner == workspace.transcript.selectedID else { return false }
        return try await access.withAccess(files) {
            guard !Task.isCancelled, owner == workspace.transcript.selectedID else { return false }
            return await workspace.pickFiles(files)
        }
    }
}
