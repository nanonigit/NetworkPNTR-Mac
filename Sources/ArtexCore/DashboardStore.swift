import Foundation
import Observation

public struct DashboardLoadState<Value: Sendable>: Sendable {
    public var value: Value?
    public var isLoading = false
    public var error: String? { failure?.text(language: .japanese) }
    public var failure: AppErrorMessage?
    public var updatedAt: Date?
}

@MainActor @Observable public final class DashboardStore {
    public private(set) var tasks = DashboardLoadState<[DashboardTask]>()
    public private(set) var fast = DashboardLoadState<DashboardFastData>()
    public private(set) var slow = DashboardLoadState<DashboardSlowData>()
    public var source: DashboardTokenSource = .old
    public var selection: DashboardProfileSelection = .all
    public var days = 30
    @ObservationIgnored private let service: DashboardService
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var polling = false
    public init(service: DashboardService) { self.service = service }
    public var snapshot: DashboardSnapshot {
        .init(tasks: tasks.value ?? [], fast: fast.value ?? .empty, slow: slow.value ?? .empty)
    }
    public var tokensAvailable: Bool { tasks.value != nil && fast.value != nil && slow.value != nil }
    public func metrics(now: Date = Date(), calendar: Calendar = .current) throws -> DashboardMetrics {
        try DashboardMetrics(snapshot: snapshot, source: source, selection: selection, days: days, now: now, calendar: calendar)
    }
    public func refreshTasks() async {
        guard !tasks.isLoading else { return }
        let ticket = generation; tasks.isLoading = true
        defer { if ticket == generation { tasks.isLoading = false } }
        do {
            let value = try await service.tasks()
            guard ticket == generation, !Task.isCancelled else { return }
            tasks.value = value; tasks.failure = nil; tasks.updatedAt = Date()
        } catch {
            if ticket == generation, !Task.isCancelled { tasks.failure = AppErrorMessage(error) }
        }
    }
    public func refreshFast() async {
        guard !fast.isLoading else { return }
        let ticket = generation; fast.isLoading = true
        defer { if ticket == generation { fast.isLoading = false } }
        do {
            let value = try await service.fast()
            guard ticket == generation, !Task.isCancelled else { return }
            fast.value = value; fast.failure = nil; fast.updatedAt = Date()
        } catch {
            if ticket == generation, !Task.isCancelled { fast.failure = AppErrorMessage(error) }
        }
    }
    public func refreshSlow() async {
        guard !slow.isLoading else { return }
        let ticket = generation; slow.isLoading = true
        defer { if ticket == generation { slow.isLoading = false } }
        do {
            let value = try await service.slow()
            guard ticket == generation, !Task.isCancelled else { return }
            slow.value = value; slow.failure = nil; slow.updatedAt = Date()
        } catch {
            if ticket == generation, !Task.isCancelled { slow.failure = AppErrorMessage(error) }
        }
    }
    public func refreshAll() async {
        async let a: Void = refreshTasks()
        async let b: Void = refreshFast()
        async let c: Void = refreshSlow()
        _ = await (a, b, c)
    }
    public func stop() {
        generation = UUID(); polling = false
        tasks.isLoading = false; fast.isLoading = false; slow.isLoading = false
    }
    public func run() async {
        guard !polling else { return }
        polling = true; let ticket = generation
        async let a: Void = poll(.tasks, seconds: 5, ticket: ticket)
        async let b: Void = poll(.fast, seconds: 5, ticket: ticket)
        async let c: Void = poll(.slow, seconds: 15, ticket: ticket)
        _ = await (a, b, c)
        if generation == ticket { stop() }
    }
    private enum Group { case tasks, fast, slow }
    private func poll(_ group: Group, seconds: UInt64, ticket: UUID) async {
        while generation == ticket && !Task.isCancelled {
            switch group { case .tasks: await refreshTasks(); case .fast: await refreshFast(); case .slow: await refreshSlow() }
            do { try await Task.sleep(nanoseconds: seconds * 1_000_000_000) } catch { return }
        }
    }
}
