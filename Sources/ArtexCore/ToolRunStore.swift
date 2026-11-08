import Foundation
import Observation

/// A view-owned history snapshot. List and tally reads have independent lifetimes.
@MainActor @Observable public final class ToolRunStore {
    public private(set) var list = FindingReadState<ToolRunPage>()
    public private(set) var stats = FindingReadState<[ToolRunTally]>()
    public private(set) var filter = ToolRunFilter()
    public private(set) var page: Int64 = 0
    public private(set) var pageSize = 50

    @ObservationIgnored private let service: ToolRunService

    public init(service: ToolRunService) { self.service = service }

    public var hasPrevious: Bool { page > 0 }
    public var hasNext: Bool {
        guard !list.isStale, let total = list.value?.total, total > 0 else { return false }
        return page < (total - 1) / Int64(pageSize)
    }

    public func setFilter(_ filter: ToolRunFilter) {
        guard self.filter != filter else { return }
        self.filter = filter
        page = 0
        // Detach the previous reads even if an observer changes the filter during publication.
        list = FindingReadState()
        stats = FindingReadState()
    }

    @discardableResult public func setPageSize(_ size: Int) -> Bool {
        guard ToolRunService.pageSizes.contains(size) else { return false }
        if pageSize != size {
            pageSize = size
            page = 0
            list = FindingReadState()
        }
        return true
    }

    @discardableResult public func setPage(_ page: Int64) -> Bool {
        guard page >= 0, page <= Int64.max / Int64(pageSize) else { return false }
        if self.page != page {
            self.page = page
            list = FindingReadState()
        }
        return true
    }

    public func refreshList() async {
        let filter = filter
        let page = page
        let size = pageSize
        await list.refresh { try await service.list(filter: filter, page: page, size: size) }
    }

    public func refreshStats() async {
        let filter = filter
        await stats.refresh { try await service.stats(filter: filter) }
    }

    public func reset() {
        filter = ToolRunFilter()
        page = 0
        pageSize = 50
        list = FindingReadState()
        stats = FindingReadState()
    }
}
