import Foundation

/// Developer-owned request boundary, never serialized or supplied by a guest.
/// Handoff means the transport may act; it does not prove delivery or commit.
@MainActor public final class TaskRequestHandoff {
    public private(set) var wasDispatched = false
    private let validate: @MainActor () throws -> Void
    public init(validate: @escaping @MainActor () throws -> Void = {}) { self.validate = validate }
    func begin() throws {
        try Task.checkCancellation()
        guard !wasDispatched else { throw BackendAPIError.invalidResponse }
        try validate(); try Task.checkCancellation(); wasDispatched = true
    }
}
