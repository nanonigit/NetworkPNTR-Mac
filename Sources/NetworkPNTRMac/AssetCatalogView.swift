import NetworkPNTRCore
import SwiftUI

@MainActor struct AssetCatalogView: View {
    @Environment(\.locale) private var locale
    private let service: AssetCatalogService
    @State private var store: AssetCatalogStore
    @State private var draft = ""
    @State private var reload = 0
    @State private var selected: Set<Int64> = []
    @State private var pendingDeletion: AssetCatalogStore.Deletion?
    @State private var selectedCompanyID: Int64?
    @State private var companyAction: CompanyEditorAction?
    @State private var companyResult: CompanyEditorResult?

    init(session: AuthenticationSession) {
        let service = AssetCatalogService(client: AuthenticatedBackendClient(session: session))
        self.service = service
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
                if !selected.isEmpty {
                    Button(countLabel(.assetCatalogDeleteSelected, Int64(selected.count)), role: .destructive) {
                        pendingDeletion = store.prepareDeletion(ids: selected.sorted())
                    }
                    .disabled(!store.canDeleteAssets)
                }
                Button(s(.companyAdd)) { companyAction = .create }
                Button(s(.toolRunRefresh)) { reload += 1 }
                    .disabled(store.page.isLoading || store.companies.isLoading || store.counts.isLoading)
            }
            if let result = companyResult {
                Text(companyResultText(result)).foregroundStyle(.secondary)
                if !result.warnings.isEmpty {
                    Text(s(.companyScopeWarning)).foregroundStyle(.orange)
                    ForEach(result.warnings.indices, id: \.self) { index in
                        Text(verbatim: result.warnings[index]).foregroundStyle(.secondary)
                    }
                }
            }
            if let count = store.deletedCount {
                Text(countLabel(.assetCatalogDeleted, count)).foregroundStyle(.secondary)
            }
            if store.deletionUnconfirmed {
                Text(s(.assetCatalogDeleteUnconfirmed)).foregroundStyle(.red)
            }
            Picker(s(.assets), selection: Binding(get: { store.query.type }, set: { type in
                selected.removeAll()
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
        .disabled(store.isDeleting)
        .alert(s(.assetCatalogDeleteTitle), isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        ), presenting: pendingDeletion) { deletion in
            Button(s(.findingUICancel), role: .cancel) {}
            Button(s(.assetCatalogDelete), role: .destructive) {
                pendingDeletion = nil
                Task {
                    if await store.deleteAssets(deletion) {
                        selected.removeAll()
                        reload += 1
                    }
                }
            }
        } message: { deletion in
            Text(countLabel(.assetCatalogDeleteBody, Int64(deletion.ids.count)))
        }
        .onChange(of: request) { _, _ in pendingDeletion = nil }
        .sheet(item: $companyAction) { action in
            CompanyEditor(action: action, locale: locale, service: service, refresh: {
                store.invalidateCatalog()
                reload += 1
            }, completed: { companyResult = $0 })
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
        let companies = store.companies.value ?? []
        return VStack(alignment: .leading) {
            if let failure = store.companies.failure { error(failure) }
            Table(companies, selection: $selectedCompanyID) {
                TableColumn(s(.assetCatalogName)) { company in literal(company.name) }
                TableColumn(s(.assetCatalogCount)) { company in Text(company.assetCount, format: .number) }
                TableColumn(s(.assetCatalogScope)) { company in
                    literal(company.scope?.map(\.raw).joined(separator: ", "))
                }
                TableColumn(s(.companyActions)) { company in
                    companyActions(company)
                        .buttonStyle(.borderless)
                }
                .width(min: 210, ideal: 235)
            }
            .overlay {
                if store.companies.isLoading { ProgressView() }
                else if store.companies.value?.isEmpty == true, !store.companies.isStale { empty }
            }
            if let company = companies.first(where: { $0.id == selectedCompanyID }) {
                HStack {
                    Text(verbatim: company.name).lineLimit(1).foregroundStyle(.secondary)
                    Spacer()
                    companyActions(company)
                }
            }
        }
    }

    private func companyActions(_ company: AssetCatalogCompany) -> some View {
        HStack {
            Button(s(.companyReplace)) { companyAction = .replace(company) }
            Button(s(.companyAppend)) { companyAction = .append(company) }
            Button(s(.companyDelete), role: .destructive) { companyAction = .delete(company) }
        }
        .disabled(store.companies.isStale)
    }

    private func assetContent(_ type: AssetCatalogType) -> some View {
        let rows = store.page.value?.assets ?? []
        return VStack(alignment: .leading, spacing: 8) {
            AssetDSLSearchField(text: $draft, failure: store.page.failure)
                .id(type)
                .onChange(of: draft) { _, value in store.search(value) }
            if type == .rootDomain, let failure = store.companies.failure { error(failure) }
            Table(rows, selection: visibleSelection(rows)) {
                TableColumn(s(.assetCatalogSelect)) { row in
                    Toggle(s(.assetCatalogSelect), isOn: Binding(
                        get: { selected.contains(row.id) },
                        set: { if $0 { selected.insert(row.id) } else { selected.remove(row.id) } }
                    ))
                    .labelsHidden()
                }
                .width(54)
                TableColumnForEach(columns(type)) { column in
                    TableColumn(column.title) { row in
                        if let url = column.destination?(row) {
                            Link(destination: url) { literal(column.value(row)) }
                                .help(url.absoluteString)
                        } else {
                            literal(column.value(row))
                        }
                    }
                }
                TableColumn(s(.assetCatalogDelete)) { row in
                    Button {
                        pendingDeletion = store.prepareDeletion(ids: [row.id])
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(s(.assetCatalogDelete))
                    .disabled(!store.canDeleteAssets)
                }
                .width(62)
            }
            .id(type)
            .onDeleteCommand {
                pendingDeletion = store.prepareDeletion(ids: selected.sorted())
            }
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
                if !rows.isEmpty, !store.page.isStale {
                    let ids = Set(rows.map(\.id))
                    let allSelected = ids.isSubset(of: selected)
                    Button(s(allSelected ? .assetCatalogDeselectPage : .assetCatalogSelectPage)) {
                        if allSelected { selected.subtract(ids) } else { selected.formUnion(ids) }
                    }
                }
                Spacer()
                Button(s(.toolRunPrevious)) { store.setPage(store.query.page - 1) }
                    .disabled(store.query.page == 0 || store.page.isLoading)
                Button(s(.toolRunNext)) { store.setPage(store.query.page + 1) }
                    .disabled(!store.hasNext || store.page.isLoading)
            }
        }
    }

    private func visibleSelection(_ rows: [AssetCatalogRow]) -> Binding<Set<Int64>> {
        let visibleIDs = Set(rows.map(\.id))
        return Binding(
            get: { selected.intersection(visibleIDs) },
            set: { selected = selected.subtracting(visibleIDs).union($0.intersection(visibleIDs)) }
        )
    }

    private struct Column: Identifiable {
        let title: String
        var destination: ((AssetCatalogRow) -> URL?)?
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
                            [String(port.port), port.service.flatMap { $0.isEmpty ? nil : $0 }]
                                .compactMap { $0 }.joined(separator: "/")
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
                    .init(title: domain.title, destination: { $0.httpServiceDestination }) { row in
                        if let domain = row.domain, !domain.isEmpty { return domain }
                        return row.serviceType == "http" ? row.url : nil
                    }, ip,
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
        case .app: s(.assetCatalogApplication)
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

    private func countLabel(_ key: AppStringKey, _ count: Int64) -> String {
        s(key).replacingOccurrences(of: "{count}", with: count.formatted(.number.locale(locale)))
    }

    private func companyResultText(_ result: CompanyEditorResult) -> String {
        var text = s(result.message)
        let values = ["added": Int64(result.added), "invalid": Int64(result.invalid),
                      "skipped": Int64(result.skipped), "assets": result.assets]
        for (key, value) in values {
            text = text.replacingOccurrences(of: "{\(key)}", with: value.formatted(.number.locale(locale)))
        }
        return text
    }

    private var language: AppLanguage { .preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
}
