import Observation

@MainActor @Observable public final class LLMRecordStore {
    public private(set) var list = FindingReadState<LLMRecordPage>()
    public let recording = FindingReadState<Bool>()
    public private(set) var isMutating = false
    public private(set) var mutationFailure: AppErrorMessage?
    public private(set) var deletedCount: Int64?
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

    public func refreshRecording() async {
        guard !isMutating else { return }
        await recording.refresh { try await service.recordingEnabled() }
    }

    public func setRecording(_ enabled: Bool) async {
        guard !isMutating, !recording.isLoading, !recording.isStale,
              let previous = recording.value, previous != enabled else { return }
        isMutating = true
        mutationFailure = nil
        deletedCount = nil
        defer { isMutating = false }
        do {
            let actual = try await service.setRecording(enabled)
            recording.acceptConfirmed(actual)
            if actual != enabled { mutationFailure = AppErrorMessage(BackendAPIError.invalidResponse) }
        } catch {
            recording.invalidate(clear: true)
            mutationFailure = AppErrorMessage(error)
        }
    }

    public func delete(task: String) async -> Bool {
        guard !isMutating, !tasks.isStale,
              tasks.value?.contains(where: { $0.taskId.utf8.elementsEqual(task.utf8) }) == true else { return false }
        isMutating = true
        mutationFailure = nil
        deletedCount = nil
        defer {
            // A failed reply can arrive after the guest committed a deletion.
            list.invalidate(clear: true)
            tasks.invalidate(clear: true)
            isMutating = false
        }
        do {
            deletedCount = try await service.delete(task: task)
            if filter.task.utf8.elementsEqual(task.utf8) {
                filter = .init(model: filter.model, session: filter.session)
            }
            page = 0
            return true
        } catch {
            mutationFailure = AppErrorMessage(error)
            return false
        }
    }

    public func detailState() -> FindingReadState<LLMRecordDetail> { FindingReadState() }

    public func loadDetail(id: Int64, into state: FindingReadState<LLMRecordDetail>) async {
        await state.refresh { try await service.detail(id: id) }
    }
}
