import Foundation
import Observation

/// Last-good finite reads are owned by a generation; invalidation never lets old cleanup affect a new read.
@MainActor @Observable public final class FindingReadState<Value: Sendable> {
    public private(set) var value: Value?
    public private(set) var isLoading = false
    public private(set) var isStale = true
    public private(set) var failure: AppErrorMessage?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var acquiring = false
    init() {}
    @discardableResult func refresh(_ load: @MainActor () async throws -> Value) async -> Bool {
        guard !acquiring, !isLoading, !Task.isCancelled else { return false }
        acquiring = true
        let ticket = UUID(); generation = ticket; isLoading = true
        acquiring = false
        // No read has suspended yet: notification invalidation must defeat the pending busy assignment.
        guard generation == ticket else { isLoading = false; return false }
        defer { if generation == ticket { isLoading = false } }
        do {
            try Task.checkCancellation()
            let result = try await load(); try Task.checkCancellation()
            guard generation == ticket else { return false }
            value = result; isStale = false; failure = nil; return true
        } catch {
            guard generation == ticket else { return false }
            isStale = true
            if !Task.isCancelled, !(error is CancellationError) { failure = AppErrorMessage(error) }
            return false
        }
    }
    func invalidate(clear: Bool = false) {
        generation = UUID(); isLoading = false; isStale = true
        if clear { value = nil; failure = nil }
    }
    func mutateCached(_ change: (Value) -> Value) {
        invalidate()
        if let value { self.value = change(value) }
    }
    /// A verified write response is a fresh snapshot and supersedes older reads.
    func acceptConfirmed(_ value: Value) {
        generation = UUID(); self.value = value; isLoading = false; isStale = false; failure = nil
    }
}
public protocol FindingPagedValue: Sendable {
    var total: Int64 { get }
    var page: Int64 { get }
    var pageSize: Int { get }
}
extension FindingPage: FindingPagedValue {}
extension FindingGroupsPage: FindingPagedValue {}

/// Correct an out-of-range cursor once, after an owned successful read; no unbounded read loop.
@MainActor @Observable public final class FindingPageState<Value: FindingPagedValue> {
    public private(set) var page: Int64 = 1
    public private(set) var size: Int
    public let read = FindingReadState<Value>()
    @ObservationIgnored private let initialSize: Int
    @ObservationIgnored private let maximum: Int
    init(size: Int,maximum: Int) { self.size = size; initialSize = size; self.maximum = maximum }
    @discardableResult func configure(page: Int64,size: Int) -> Bool {
        guard page > 0, (1...maximum).contains(size), page-1 <= Int64.max/Int64(size) else { return false }
        if self.page != page || self.size != size { self.page = page; self.size = size; read.invalidate(clear:true) }
        return true
    }
    @discardableResult func refresh(_ load: @MainActor (Int64,Int) async throws -> Value) async -> Bool {
        let requestedPage = page, requestedSize = size
        guard await read.refresh({try await load(requestedPage,requestedSize)}), let value = read.value else { return false }
        let last = value.total == 0 ? 1 : (value.total-1)/Int64(requestedSize)+1
        guard requestedPage > last else { return true }
        guard configure(page:last,size:requestedSize) else { return false }
        return await read.refresh {try await load(last,requestedSize)}
    }
    func reset() { page = 1; size = initialSize; read.invalidate(clear:true) }
}
