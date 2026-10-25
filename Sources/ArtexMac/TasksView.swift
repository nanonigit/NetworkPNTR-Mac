import ArtexCore
import SwiftUI

@MainActor struct TasksView: View {
    let model: TaskScreenModel
    @Binding var requestedID: String?
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    var body: some View {
        let sheetID = model.dialog?.id
        let creationID = model.creation?.context?.id
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(s(.taskUITitle)).font(.largeTitle.bold())
                Spacer()
                if model.creation != nil {
                    Button(s(.taskCreateTitle), systemImage: "plus") { _ = model.beginCreate() }.disabled(model.busy || model.dialog != nil || model.creation?.context != nil)
                }
                if model.store.list.isLoading { ProgressView().controlSize(.small) }
                Button(s(.taskUIRefresh), systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                    .keyboardShortcut("r", modifiers: .command).disabled(model.busy)
            }
            filters
            TaskOperationNotice(store: model.store)
            if let failure = model.store.list.failure { Text(failure.text(language: language)).foregroundStyle(.red).textSelection(.enabled) }
            if model.store.list.isStale, model.store.list.value != nil { Text(s(.taskUIStale)).font(.caption).foregroundStyle(.secondary) }
            HSplitView {
                taskTable.frame(minWidth: 380)
                TaskDetailView(model: model).frame(minWidth: 280, idealWidth: 350, maxWidth: 480)
            }
        }
        .padding(20).navigationTitle(s(.taskUITitle))
        .sheet(item: Binding(get: { model.dialog }, set: { if $0 == nil, let sheetID { model.closeDialog(id: sheetID) } })) { context in TaskDialogView(model: model, contextID: context.id) }
        .sheet(item: Binding(get: { model.creation?.context }, set: { if $0 == nil, let creationID { model.creation?.close(contextID: creationID) } })) { context in
            if let creation = model.creation { TaskCreateView(model: creation, contextID: context.id) }
        }
        .task {
            if let id = requestedID {
                requestedID = nil; model.query = ""; model.status = nil
                await model.store.select(id: id)
            }
            await model.store.run()
        }
        .onDisappear { model.stop() }
    }
    private var filters: some View {
        HStack {
            TextField(s(.taskUISearch), text: Binding(get: { model.query }, set: { model.query = $0 }))
                .textFieldStyle(.roundedBorder).accessibilityLabel(s(.taskUISearch))
            Picker(s(.taskUIStatus), selection: Binding(get: { model.status ?? "all" }, set: { model.status = $0 == "all" ? nil : $0 })) {
                Text(s(.taskUIAll)).tag("all")
                ForEach(TaskPresentation.statuses, id: \.self) { status in Text(DashboardLabels.text(status, domain: .task, language: language)).tag(status) }
            }.frame(maxWidth: 180)
            Picker(s(.taskUISort), selection: Binding(get: { model.sort }, set: { model.sort = $0 })) {
                Text(s(.taskUIID)).tag(TaskSortField.id); Text(s(.taskUICreated)).tag(TaskSortField.created)
                Text(s(.taskUIDuration)).tag(TaskSortField.duration); Text(s(.taskUIStatus)).tag(TaskSortField.status)
            }.frame(maxWidth: 160)
            Button(model.ascending ? s(.taskUIAscending) : s(.taskUIDescending), systemImage: model.ascending ? "arrow.up" : "arrow.down") { model.ascending.toggle() }
                .labelStyle(.iconOnly).help(model.ascending ? s(.taskUIAscending) : s(.taskUIDescending))
        }
    }
    private var taskTable: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let rows = TaskPresentation.rows(model.store.list.value ?? [], query: model.query, status: model.status,
                                             sort: model.sort, ascending: model.ascending, now: Int64(context.date.timeIntervalSince1970))
            Table(rows, selection: Binding(get: { model.store.selectedID }, set: { model.select($0) })) {
                TableColumn(s(.taskUIName)) { item in
                    HStack {
                        if item.pinned { Image(systemName: "pin.fill").accessibilityLabel(s(.taskUIPin)) }
                        VStack(alignment: .leading) {
                            Text(item.name.isEmpty ? AppStrings.formatted(.taskUIUnnamed, language: language, values: ["id": item.id]) : item.name).lineLimit(1)
                            Text(item.id).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.width(min: 130, ideal: 180)
                TableColumn(s(.taskUIStatus)) { item in Text(DashboardLabels.text(item.status, domain: .task, language: language)) }.width(min: 70, ideal: 90)
                TableColumn(s(.taskUIGoals)) { item in Text("\(item.goalsMet)/\(item.goalsTotal)").monospacedDigit() }.width(min: 48, ideal: 55)
                TableColumn(s(.taskUITokens)) { item in Text(TaskPresentation.tokens(item)).monospacedDigit().help(AppStrings.formatted(.taskUITokenBreakdown, language: language, values: ["input": String(item.tokens.inputTokens), "read": String(item.tokens.cacheReadTokens), "write": String(item.tokens.cacheWriteTokens), "output": String(item.tokens.outputTokens)])) }.width(min: 80, ideal: 100)
                TableColumn(s(.taskUIDuration)) { item in Text(TaskPresentation.duration(item, now: Int64(context.date.timeIntervalSince1970)) > 0 ? TaskPresentation.durationText(TaskPresentation.duration(item, now: Int64(context.date.timeIntervalSince1970)), language: language) : "—") }.width(min: 65, ideal: 80)
            }
            .overlay {
                if rows.isEmpty {
                    if model.store.list.value == nil && model.store.list.isLoading { ProgressView(s(.taskUILoading)) }
                    else if model.store.list.value != nil {
                        ContentUnavailableView(model.query.isEmpty && model.status == nil && model.store.list.value?.isEmpty == true ? s(.taskUIEmpty) : s(.taskUINoMatch), systemImage: "checklist")
                    }
                }
            }
        }
    }
}
