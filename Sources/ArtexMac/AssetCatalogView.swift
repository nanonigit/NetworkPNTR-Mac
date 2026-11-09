import ArtexCore
import SwiftUI

@MainActor struct AssetCatalogView: View {
    @Environment(\.locale) private var locale
    @State private var store: AssetCatalogStore
    @State private var draft = ""
    @State private var reload = 0

    init(session: AuthenticationSession) {
        let service = AssetCatalogService(client: AuthenticatedBackendClient(session: session))
        _store = State(initialValue: AssetCatalogStore(service: service))
    }

    private struct Request: Equatable {
        let query: AssetCatalogStore.Query
        let reload: Int
    }

    var body: some View {
        let request = Request(query: store.query, reload: reload)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(s(.assets)).font(.largeTitle.bold())
                Spacer()
                Button(s(.toolRunRefresh)) { reload += 1 }
            }
            Text(s(.assetCatalogReadOnly)).foregroundStyle(.secondary)
            Picker(s(.assets), selection: Binding(get: { store.query.type }, set: { type in
                draft = ""
                store.select(type)
            })) {
                tab(s(.assetCatalogCompany), count: store.companies.value?.count).tag(nil as AssetCatalogType?)
                ForEach(AssetCatalogType.allCases, id: \.self) { type in
                    tab(title(type), count: store.counts.value?[type.rawValue]).tag(Optional(type))
                }
            }
            .pickerStyle(.segmented)
            if let failure = store.counts.failure { error(failure) }
            if let type = store.query.type {
                assetContent(type)
            } else {
                companyContent
            }
        }
        .padding()
        .navigationTitle(s(.assets))
        .task(id: request) {
            if !request.query.dsl.isEmpty {
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            }
            await store.refreshPage(request.query)
        }
        .task(id: reload) { await store.refreshCompanies() }
        .task(id: reload) { await store.refreshCounts() }
    }

    private var companyContent: some View {
        VStack(alignment: .leading) {
            if let failure = store.companies.failure { error(failure) }
            Table(store.companies.value ?? []) {
                TableColumn(s(.assetCatalogName)) { company in literal(company.name) }
                TableColumn(s(.assetCatalogCount)) { company in Text(company.assetCount, format: .number) }
                TableColumn(s(.assetCatalogScope)) { company in
                    literal(company.scope?.map(\.raw).joined(separator: ", "))
                }
            }
            .overlay {
                if store.companies.isLoading { ProgressView() }
                else if store.companies.value?.isEmpty == true, !store.companies.isStale { empty }
            }
        }
    }

    private func assetContent(_ type: AssetCatalogType) -> some View {
        let rows = store.page.value?.assets ?? []
        return VStack(alignment: .leading, spacing: 8) {
            TextField(s(.assetCatalogSearch), text: $draft)
                .textFieldStyle(.roundedBorder)
                .onChange(of: draft) { _, value in store.search(value) }
            if let failure = store.page.failure { error(failure) }
            if type == .rootDomain, let failure = store.companies.failure { error(failure) }
            Table(rows) {
                TableColumnForEach(columns(type)) { column in
                    TableColumn(column.title) { row in literal(column.value(row)) }
                }
            }
            .id(type)
            .overlay {
                if store.page.isLoading { ProgressView() }
                else if store.page.value?.total == 0, !store.page.isStale { empty }
            }
            HStack {
                Picker(s(.toolRunPageSize), selection: Binding(get: { store.query.size }, set: store.setSize)) {
                    ForEach(AssetCatalogService.pageSizes, id: \.self) { Text($0, format: .number).tag($0) }
                }
                .fixedSize()
                if let page = store.page.value, !store.page.isStale {
                    let range = ToolRunPresentation.pageRange(page: store.query.page, size: store.query.size, count: rows.count)
                    Text("\(range.first, format: .number)–\(range.last, format: .number) / \(page.total, format: .number)")
                        .monospacedDigit()
                }
                Spacer()
                Button(s(.toolRunPrevious)) { store.setPage(store.query.page - 1) }
                    .disabled(store.query.page == 0 || store.page.isLoading)
                Button(s(.toolRunNext)) { store.setPage(store.query.page + 1) }
                    .disabled(!store.hasNext || store.page.isLoading)
            }
        }
    }

    private struct Column: Identifiable {
        let title: String
        let value: (AssetCatalogRow) -> String?
        var id: String { title }
    }

    private func columns(_ type: AssetCatalogType) -> [Column] {
        let domain = Column(title: s(.assetCatalogDomain), value: \.domain)
        let ip = Column(title: "IP", value: \.ip)
        switch type {
        case .rootDomain:
            let owners = Dictionary(uniqueKeysWithValues: (store.companies.value ?? []).map { ($0.id, $0.name) })
            return [domain, .init(title: "ICP", value: \.icp),
                    .init(title: s(.assetCatalogOwner)) { row in
                        guard let id = row.companyId else { return s(.assetCatalogUnassigned) }
                        return owners[id] ?? String(id)
                    }]
        case .ip:
            return [ip, .init(title: s(.assetCatalogSegment), value: \.cSegment),
                    .init(title: s(.assetCatalogBoundDomains)) { $0.boundDomains?.joined(separator: ", ") },
                    .init(title: s(.assetCatalogOpenPorts)) { row in
                        row.openPorts?.map { port in
                            [String(port.port), port.service].compactMap { $0 }.joined(separator: " ")
                        }.joined(separator: ", ")
                    }]
        case .subdomain:
            return [domain, .init(title: s(.assetCatalogRootDomain), value: \.rootDomain),
                    .init(title: s(.assetCatalogRecordType), value: \.recordType),
                    .init(title: s(.assetCatalogRecordValue)) { $0.recordValue?.joined(separator: ", ") }]
        case .app:
            return [.init(title: s(.assetCatalogApp), value: \.appName), .init(title: "Bundle ID", value: \.bundleId),
                    .init(title: s(.assetCatalogCategory), value: \.category), .init(title: "ICP", value: \.appIcp)]
        case .service:
            return [.init(title: s(.assetCatalogService)) { $0.serviceName ?? $0.serviceType },
                    .init(title: domain.title) { $0.domain ?? $0.url }, ip,
                    .init(title: s(.assetCatalogPort)) { $0.port.map(String.init) },
                    .init(title: s(.assetCatalogStatusCode)) { $0.statusCode.map(String.init) },
                    .init(title: s(.assetCatalogTitle), value: \.pageTitle),
                    .init(title: s(.assetCatalogTechnologies)) { $0.technologies?.joined(separator: ", ") },
                    .init(title: s(.assetCatalogAuth)) { $0.auth?.compactMap { $0.type ?? $0.username }.joined(separator: ", ") }]
        case .endpoint:
            return [.init(title: s(.assetCatalogMethod), value: \.method), .init(title: "URL", value: \.url),
                    .init(title: s(.assetCatalogParameters)) { row in
                        row.params?.map { item in
                            guard let name = item.name else { return "?" }
                            return "\(name)(\(item.location ?? "?"))"
                        }.joined(separator: ", ")
                    }]
        }
    }

    private func title(_ type: AssetCatalogType) -> String {
        switch type {
        case .rootDomain: s(.assetCatalogRootDomain)
        case .ip: "IP"
        case .subdomain: s(.assetCatalogSubdomain)
        case .app: s(.assetCatalogApp)
        case .service: s(.assetCatalogService)
        case .endpoint: s(.assetCatalogEndpoint)
        }
    }

    private func tab<Count: BinaryInteger>(_ title: String, count: Count?) -> Text {
        guard let count else { return Text(verbatim: title) }
        return Text(verbatim: "\(title) \(Int64(count).formatted(.number.locale(locale)))")
    }

    private func literal(_ value: String?) -> Text {
        Text(verbatim: value.flatMap { $0.isEmpty ? nil : $0 } ?? "—")
    }

    private var empty: some View { Text(s(.assetCatalogEmpty)).foregroundStyle(.secondary) }

    private func error(_ failure: AppErrorMessage) -> some View {
        Text(failure.text(language: language)).foregroundStyle(.red)
    }

    private var language: AppLanguage { .preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
}
