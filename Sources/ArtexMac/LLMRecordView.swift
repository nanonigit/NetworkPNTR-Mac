import AppKit
import ArtexCore
import Foundation
import SwiftUI

@MainActor struct LLMRecordView: View {
    @Environment(\.locale) private var locale
    @State private var store: LLMRecordStore
    @State private var model = ""
    @State private var sessionQuery = ""
    @State private var task = Data()
    @State private var selectedID: Int64?
    @State private var detail: LLMRecord?
    @State private var prefersRawDetail = false
    @State private var reload = 0
    @State private var deletionTask: String?

    init(session: AuthenticationSession) {
        let service = LLMRecordService(client: AuthenticatedBackendClient(session: session))
        _store = State(initialValue: LLMRecordStore(service: service))
    }

    private struct Request: Equatable {
        let filter: LLMRecordFilter
        let page: Int64
        let size: Int
        let reload: Int
    }

    private var request: Request {
        .init(filter: store.filter, page: store.page, size: store.size, reload: reload)
    }
    private var rows: [LLMRecord] { store.list.value?.records ?? [] }
    private var language: AppLanguage { .preferred(in: [locale.identifier]) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(s(.llmRecords)).font(.largeTitle.bold())
                if let total = store.list.value?.total { Text(total, format: .number).foregroundStyle(.secondary) }
                Spacer()
                if let recording = store.recording.value {
                    Toggle(s(.llmRecordRecording), isOn: Binding(get: { recording }, set: { enabled in
                        Task { await store.setRecording(enabled) }
                    }))
                    .toggleStyle(.switch)
                    .disabled(store.isMutating || store.recording.isStale || store.recording.isLoading)
                }
            }
            HStack {
                TextField(s(.llmRecordSession), text: $sessionQuery).onSubmit(apply)
                TextField(s(.llmUIModel), text: $model).onSubmit(apply)
                Picker(s(.llmRecordTask), selection: $task) {
                    Text(s(.llmRecordAllTasks)).tag(Data())
                    ForEach(store.tasks.value ?? [], id: \.wireIdentity) { row in
                        Text(verbatim: "#\(row.taskId) (\(row.count.formatted(.number.locale(locale))))")
                            .tag(row.wireIdentity)
                    }
                }
                Button(s(.toolRunApply), action: apply)
                Picker(s(.toolRunPageSize), selection: Binding(get: { store.size }, set: store.setSize)) {
                    ForEach(LLMRecordService.pageSizes, id: \.self) { Text($0, format: .number).tag($0) }
                }.fixedSize()
            }
            .disabled(store.isMutating)
            if let failure = store.recording.failure { error(failure, label: .llmRecordRecording) }
            if let failure = store.mutationFailure { error(failure, label: .llmRecords) }
            if let deleted = store.deletedCount {
                Text(s(.llmRecordDeleted).replacingOccurrences(of: "{count}", with: deleted.formatted(.number.locale(locale))))
                    .foregroundStyle(.secondary)
            }
            if let failure = store.tasks.failure { error(failure, label: .llmRecordTask) }
            if let failure = store.list.failure { error(failure, label: .llmRecords) }
            Table(rows, selection: $selectedID) {
                TableColumn(s(.toolRunTime)) { row in llmRecordTimestamp(row.ts, locale: locale) }.width(min: 104, ideal: 122)
                TableColumn(s(.llmRecordTask)) { row in literal(row.taskId) }.width(min: 52, ideal: 58)
                TableColumn(s(.toolRunWorker)) { row in literal(row.worker) }.width(min: 55, ideal: 57)
                TableColumn(s(.llmRecordProfile)) { row in literal(row.profileName) }.width(min: 55, ideal: 60)
                TableColumn(s(.llmUIModel)) { row in literal(row.model) }.width(min: 84, ideal: 92)
                TableColumn(s(.llmRecordLatency)) { row in Text(row.latencyMs, format: .number) }.width(min: 62, ideal: 68)
                TableColumn(s(.llmRecordTokens)) { row in
                    Text("\(row.inputTokens, format: .number) / \(row.outputTokens, format: .number)")
                }.width(min: 52, ideal: 58)
                TableColumn(s(.toolRunStatus)) { row in
                    Text(s(row.status == "ok" ? .toolRunSucceeded : .toolRunFailed))
                        .foregroundStyle(row.status == "ok" ? Color.primary : Color.red)
                }.width(min: 60, ideal: 68)
            }
            .contextMenu(forSelectionType: Int64.self) { ids in
                if let row = rows.first(where: { ids.contains($0.id) }) {
                    Button(s(.toolRunDetails)) { detail = row }
                }
            } primaryAction: { ids in
                detail = rows.first { ids.contains($0.id) }
            }
            .disabled(store.list.isLoading || store.isMutating)
            .overlay {
                if store.list.isLoading { ProgressView() }
                else if store.list.value?.records.isEmpty == true && !store.list.isStale {
                    Text(s(.llmRecordEmpty)).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button(s(.toolRunDetails)) { detail = rows.first { $0.id == selectedID } }
                    .disabled(selectedID == nil || store.list.isLoading || store.isMutating)
                Button(s(.toolRunRefresh)) { reload += 1 }
                    .disabled(store.list.isLoading || store.tasks.isLoading || store.recording.isLoading || store.isMutating)
                Button(s(.llmRecordDeleteTask), role: .destructive) {
                    deletionTask = String(decoding: task, as: UTF8.self)
                }
                .disabled(
                    task.isEmpty || store.tasks.isStale || store.tasks.isLoading || store.isMutating
                        || store.tasks.value?.contains(where: { $0.wireIdentity == task }) != true
                )
                Spacer()
                if let result = store.list.value, !store.list.isStale {
                    let range = ToolRunPresentation.pageRange(page: store.page, size: store.size, count: rows.count)
                    Text("\(range.first, format: .number)–\(range.last, format: .number) / \(result.total, format: .number)")
                        .foregroundStyle(.secondary)
                }
                Button(s(.toolRunPrevious)) { store.setPage(store.page - 1) }.disabled(store.page == 0 || store.isMutating)
                Text(store.page + 1, format: .number).monospacedDigit()
                Button(s(.toolRunNext)) { store.setPage(store.page + 1) }.disabled(!store.hasNext || store.isMutating)
            }
        }
        .padding()
        .navigationTitle(s(.llmRecords))
        .task(id: request) { await store.refresh() }
        .task(id: reload) { await store.refreshTasks() }
        .task(id: reload) { await store.refreshRecording() }
        .onChange(of: request) { _, _ in selectedID = nil; detail = nil }
        .sheet(item: $detail) { row in
            LLMRecordDetailSheet(row: row, store: store, language: language, prefersRaw: $prefersRawDetail)
                .id(row.id)
        }
        .alert(s(.llmRecordDeleteTask), isPresented: Binding(
            get: { deletionTask != nil },
            set: { if !$0 { deletionTask = nil } }
        ), presenting: deletionTask) { target in
            Button(s(.llmRecordDeleteTask), role: .destructive) {
                deletionTask = nil
                Task {
                    if await store.delete(task: target) { task = Data() }
                    reload += 1
                }
            }
            Button(s(.trafficUICancel), role: .cancel) { deletionTask = nil }
        } message: { target in
            Text(s(.llmRecordDeletePrompt).replacingOccurrences(of: "{task}", with: target))
        }
    }

    private func apply() {
        store.apply(.init(model: model, session: sessionQuery, task: String(decoding: task, as: UTF8.self)))
    }

    private func error(_ failure: AppErrorMessage, label: AppStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(s(label)).font(.headline)
            Text(failure.text(language: language)).foregroundStyle(.red)
        }
    }

    private func literal(_ value: String) -> Text { Text(verbatim: value.isEmpty ? "—" : value) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
}

private func llmRecordTimestamp(_ value: String, locale: Locale) -> Text {
    let date = (try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        ?? (try? Date(value, strategy: Date.ISO8601FormatStyle()))
    guard let date else { return Text(verbatim: value.isEmpty ? "—" : value) }
    return Text(date, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute().second().locale(locale))
}

private extension LLMRecordTask {
    var wireIdentity: Data { Data(taskId.utf8) }
}

@MainActor private struct LLMRecordDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let row: LLMRecord
    let store: LLMRecordStore
    @State private var state: FindingReadState<LLMRecordDetail>
    let language: AppLanguage
    @Binding private var prefersRaw: Bool

    init(row: LLMRecord, store: LLMRecordStore, language: AppLanguage, prefersRaw: Binding<Bool>) {
        self.row = row
        self.store = store
        self.language = language
        _prefersRaw = prefersRaw
        _state = State(initialValue: store.detailState())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(s(.toolRunDetails)).font(.title2.bold())
            HStack {
                Text(verbatim: "#\(row.id)").monospacedDigit()
                Text(verbatim: row.model).font(.headline)
                Text(verbatim: row.profileName)
                if !row.taskId.isEmpty { Text(verbatim: "#\(row.taskId)") }
                Spacer()
                Text(s(row.status == "ok" ? .toolRunSucceeded : .toolRunFailed))
                    .foregroundStyle(row.status == "ok" ? Color.primary : Color.red)
            }
            HStack(spacing: 16) {
                LabeledContent { llmRecordTimestamp(row.ts, locale: language.locale) } label: {
                    Text(s(.toolRunTime))
                }
                LabeledContent {
                    Text(row.latencyMs, format: .number.locale(language.locale))
                } label: {
                    Text(s(.llmRecordLatency))
                }
            }
            .foregroundStyle(.secondary)
            Text(verbatim: row.sessionId).textSelection(.enabled)
            if let message = row.error, !message.isEmpty {
                Text(verbatim: message).foregroundStyle(.red).textSelection(.enabled)
            }
            if let detail = state.value {
                let hasRaw = detail.rawRequest?.isEmpty == false || detail.rawResponse?.isEmpty == false
                let showRaw = hasRaw && prefersRaw
                Toggle(s(.llmRecordRaw), isOn: Binding(
                    get: { showRaw }, set: { prefersRaw = $0 }
                ))
                .disabled(!hasRaw)
                HStack(alignment: .top, spacing: 12) {
                    payload(.llmRecordRequest, copyLabel: .llmRecordCopyRequest, showRaw ? detail.rawRequest : detail.requestBody)
                    Divider()
                    payload(.llmRecordResponse, copyLabel: .llmRecordCopyResponse, showRaw ? detail.rawResponse : detail.responseBody)
                }
            } else if let failure = state.failure {
                Text(failure.text(language: language)).foregroundStyle(.red)
            } else {
                ProgressView()
            }
            Button(s(.trafficUIClose)) { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding().frame(minWidth: 570, minHeight: 390)
        .task { await store.loadDetail(id: row.id, into: state) }
    }

    private func payload(_ label: AppStringKey, copyLabel: AppStringKey, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(s(label)).font(.headline)
                Button(s(copyLabel), systemImage: "doc.on.doc") {
                    guard let value, !value.isEmpty else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                }
                .labelStyle(.iconOnly)
                .help(s(copyLabel))
                .disabled(value?.isEmpty != false)
            }
            ScrollView {
                Text(verbatim: value.flatMap { $0.isEmpty ? nil : $0 } ?? "—")
                    .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func s(_ key: AppStringKey) -> String {
        AppStrings.text(key, language: language)
    }
}
