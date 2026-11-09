import Observation

@MainActor @Observable public final class AssetCatalogStore {
    public struct Query: Equatable, Sendable {
        public var type: AssetCatalogType?
        public var dsl = ""
        public var page: Int64 = 0
        public var size = 50

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.type == rhs.type && lhs.page == rhs.page && lhs.size == rhs.size
                && lhs.dsl.utf8.elementsEqual(rhs.dsl.utf8)
        }
    }

    public private(set) var query = Query()
    public let page = FindingReadState<AssetCatalogPage>()
    public let companies = FindingReadState<[AssetCatalogCompany]>()
    public let counts = FindingReadState<[String: Int64]>()
    @ObservationIgnored private let service: AssetCatalogService

    public init(service: AssetCatalogService) { self.service = service }

    public var hasNext: Bool {
        guard !page.isStale, let total = page.value?.total, total > 0 else { return false }
        return query.page < (total - 1) / Int64(query.size)
    }

    public func select(_ type: AssetCatalogType?) {
        update(.init(type: type, size: query.size))
    }

    public func search(_ expression: String) {
        var next = query
        next.dsl = ChatText.trim(expression)
        next.page = 0
        update(next)
    }

    public func setSize(_ size: Int) {
        guard AssetCatalogService.pageSizes.contains(size), query.size != size else { return }
        var next = query
        next.size = size
        next.page = 0
        update(next)
    }

    public func setPage(_ index: Int64) {
        guard index >= 0, index <= Int64.max / Int64(query.size) else { return }
        var next = query
        next.page = index
        update(next)
    }

    public func refreshPage(_ request: Query) async {
        guard request == query, let type = request.type else { return }
        await page.refresh {
            try await service.list(type: type, dsl: request.dsl, page: request.page, size: request.size)
        }
    }

    public func refreshCompanies() async { await companies.refresh { try await service.companies() } }
    public func refreshCounts() async { await counts.refresh { try await service.counts() } }

    private func update(_ next: Query) {
        guard next != query else { return }
        page.invalidate(clear: true)
        query = next
    }
}
