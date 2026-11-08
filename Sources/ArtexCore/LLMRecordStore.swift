import Observation

@MainActor @Observable public final class LLMRecordStore {
    public private(set) var list = FindingReadState<LLMRecordPage>()
    public let tasks = FindingReadState<[LLMRecordTask]>()
    public private(set) var filter = LLMRecordFilter()
    public private(set) var page: Int64 = 0
    public private(set) var size = 50
    @ObservationIgnored private let service: LLMRecordService

    public init(service: LLMRecordService) { self.service = service }

    public var hasNext: Bool {
        guard !list.isStale, let total = list.value?.total, total > 0 else { return false }
        return page < (total - 1) / Int64(size)
    }

    public func apply(_ filter: LLMRecordFilter) {
        guard self.filter != filter else { return }
        self.filter = filter
        page = 0
        list = FindingReadState()
    }

    public func setPage(_ page: Int64) {
        guard page >= 0, page <= Int64.max / Int64(size), self.page != page else { return }
        self.page = page
        list = FindingReadState()
    }

    public func setSize(_ size: Int) {
        guard LLMRecordService.pageSizes.contains(size), self.size != size else { return }
        self.size = size
        page = 0
        list = FindingReadState()
    }

    public func refresh() async {
        let filter = filter, page = page, size = size
        await list.refresh { try await service.list(filter: filter, page: page, size: size) }
    }

    public func refreshTasks() async {
        await tasks.refresh { try await service.tasks() }
    }

    public func detailState() -> FindingReadState<LLMRecordDetail> { FindingReadState() }

    public func loadDetail(id: Int64, into state: FindingReadState<LLMRecordDetail>) async {
        await state.refresh { try await service.detail(id: id) }
    }
}
