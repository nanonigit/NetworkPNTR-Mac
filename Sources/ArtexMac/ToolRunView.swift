import ArtexCore
import Foundation
import SwiftUI

@MainActor struct ToolRunView: View {
    @Environment(\.locale) private var locale
    @State private var store: ToolRunStore
    @State private var keyword = ""
    @State private var exploration = ""
    @State private var selection: Int?
    @State private var detail: Row?
    @State private var showsStats = false
    @State private var reload = 0

    init(session: AuthenticationSession) {
        _store = State(initialValue: ToolRunStore(service: ToolRunService(client: AuthenticatedBackendClient(session: session))))
    }

    private struct Row: Identifiable {
        let id: Int
        let run: ToolRunRecord
    }

    private struct ListRequest: Equatable {
        let filter: ToolRunFilter
        let page: Int64
        let size: Int
        let reload: Int
    }

    private var language: AppLanguage { .preferred(in: [locale.identifier]) }
    private var request: ListRequest {
        ListRequest(filter: store.filter, page: store.page, size: store.pageSize, reload: reload)
    }
    private var explorationID: Int64? { Int64(exploration) }
    private var validFilter: Bool {
        exploration.isEmpty || (explorationID.map { $0 >= 0 } ?? false)
    }
    // The result join can return multiple rows with the same tool-use ID.
    private var rows: [Row] {
        (store.list.value?.commands ?? []).enumerated().map { Row(id: $0.offset, run: $0.element) }
    }
    private var selectedRun: Row? { rows.first { $0.id == selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(s(.commands)).font(.largeTitle.bold())
                if let total = store.list.value?.total { Text(total, format: .number).foregroundStyle(.secondary) }
                Spacer()
                Button(s(.toolRunSummary)) { showsStats = true }
            }
            HStack {
                TextField(s(.toolRunSearch), text: $keyword).onSubmit(applyFilter)
                TextField(s(.toolRunExploration), text: $exploration).onSubmit(applyFilter)
                    .frame(width: 150)
                Button(s(.toolRunApply), action: applyFilter).disabled(!validFilter)
                Picker(s(.toolRunPageSize), selection: Binding(
                    get: { store.pageSize }, set: { store.setPageSize($0) }
                )) {
                    ForEach(ToolRunService.pageSizes, id: \.self) { Text($0, format: .number).tag($0) }
                }.fixedSize()
            }
            if !validFilter { Text(s(.toolRunInvalidID)).foregroundStyle(.red) }
            if let failure = store.list.failure {
                Text(failure.text(language: language)).foregroundStyle(.red)
            }
            Table(rows, selection: $selection) {
                TableColumn(s(.toolRunTime)) { row in timestamp(row.run.createdAt) }.width(min: 105, ideal: 145)
                TableColumn(s(.toolRunExploration)) { row in Text(row.run.explorationId, format: .number.grouping(.never)) }
                    .width(min: 70, ideal: 100)
                TableColumn(s(.toolRunWorker)) { row in literal(row.run.worker) }.width(min: 55, ideal: 85)
                TableColumn(s(.toolRunTool)) { row in literal(row.run.tool) }.width(min: 55, ideal: 85)
                TableColumn(s(.toolRunInput)) { row in literal(ToolRunPresentation.preview(row.run.command)).font(.system(.body, design: .monospaced)) }
                TableColumn(s(.toolRunStatus)) { row in status(row.run) }.width(min: 55, ideal: 85)
            }
            .contextMenu(forSelectionType: Int.self) { ids in
                if let run = rows.first(where: { ids.contains($0.id) }) {
                    Button(s(.toolRunDetails)) { detail = run }
                }
            } primaryAction: { ids in
                detail = rows.first { ids.contains($0.id) }
            }
            .disabled(store.list.isLoading)
            .overlay {
                if store.list.isLoading || (store.list.value == nil && store.list.failure == nil) {
                    ProgressView()
                } else if store.list.value?.commands.isEmpty == true && !store.list.isStale {
                    Text(s(.toolRunEmpty)).foregroundStyle(.secondary).padding()
                }
            }
            HStack {
                Button(s(.toolRunDetails)) { detail = selectedRun }.disabled(selectedRun == nil || store.list.isLoading)
                Button(s(.toolRunRefresh)) { reload += 1 }.disabled(store.list.isLoading)
                Spacer()
                Button(s(.toolRunPrevious)) { store.setPage(store.page - 1) }.disabled(!store.hasPrevious)
                Text((store.page + 1), format: .number).monospacedDigit()
                Button(s(.toolRunNext)) { store.setPage(store.page + 1) }.disabled(!store.hasNext)
            }
        }
        .padding()
        .navigationTitle(s(.commands))
        .task(id: request) { await store.refreshList() }
        .onChange(of: request) { _, _ in selection = nil }
        .sheet(item: $detail, content: detailSheet)
        .sheet(isPresented: $showsStats, content: summarySheet)
    }

    private func applyFilter() {
        guard validFilter else { return }
        store.setFilter(.init(explorationID: explorationID, keyword: keyword))
    }

    private func detailSheet(_ row: Row) -> some View {
        let run = row.run
        return VStack(alignment: .leading, spacing: 12) {
            Text(s(.toolRunDetails)).font(.title2.bold())
            HStack {
                timestamp(run.createdAt)
                Text(verbatim: "#\(run.explorationId)")
                literal(run.worker)
                literal(run.tool)
                status(run)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    payload(.toolRunInput, ToolRunPresentation.input(run.command))
                    payload(.toolRunOutput, run.output)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(s(.trafficUIClose)) { detail = nil }.keyboardShortcut(.cancelAction)
        }.padding().frame(minWidth: 560, minHeight: 360)
    }

    private func summarySheet() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(s(.toolRunSummary)).font(.title2.bold())
            Text(s(.toolRunSummaryScope)).foregroundStyle(.secondary)
            if store.stats.isLoading || (store.stats.value == nil && store.stats.failure == nil) {
                ProgressView()
            } else if let failure = store.stats.failure {
                Text(failure.text(language: language)).foregroundStyle(.red)
            }
            if let rows = store.stats.value {
                if rows.isEmpty {
                    Text(s(.toolRunEmpty)).foregroundStyle(.secondary)
                } else {
                    let calls = rows.reduce(Decimal.zero) { $0 + Decimal($1.total) }
                    let errors = rows.reduce(Decimal.zero) { $0 + Decimal($1.errors) }
                    HStack {
                        LabeledContent(s(.toolRunCalls)) { Text(calls, format: .number) }
                        LabeledContent(s(.toolRunFailed)) { Text(errors, format: .number) }
                    }
                    Table(rows) {
                        TableColumn(s(.toolRunTool)) { row in literal(row.tool) }
                        TableColumn(s(.toolRunCalls)) { row in Text(row.total, format: .number) }
                        TableColumn(s(.toolRunFailed)) { row in Text(row.errors, format: .number) }
                    }.frame(minHeight: 200)
                }
            }
            Button(s(.trafficUIClose)) { showsStats = false }.keyboardShortcut(.cancelAction)
        }.padding().frame(minWidth: 440)
            .task { await store.refreshStats() }
    }

    private func payload(_ title: AppStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(s(title)).font(.headline)
            literal(value).font(.system(.body, design: .monospaced)).textSelection(.enabled)
        }
    }

    private func timestamp(_ value: String) -> Text {
        let date = (try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(value, strategy: Date.ISO8601FormatStyle()))
        guard let date else { return literal(value) }
        return Text(date, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute().second().locale(locale))
    }

    private func literal(_ value: String) -> Text { Text(verbatim: value.isEmpty ? "—" : value) }
    private func status(_ run: ToolRunRecord) -> some View {
        Text(s(run.isError ? .toolRunFailed : .toolRunSucceeded))
            .foregroundStyle(run.isError ? Color.red : Color.primary)
    }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
}
