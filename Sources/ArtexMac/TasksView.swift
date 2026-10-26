import ArtexCore
import SwiftUI

@MainActor struct TasksView: View {
    let model: TaskScreenModel
    @Binding var requestedID: String?
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    var body: some View {
        let bulkID = model.bulk?.context?.id
        let ack = model.bulk?.acknowledgement
        let ackID = ack?.id
        let sheetID = model.dialog?.id
        let creationID = model.creation?.context?.id
        let categoryID = model.categories?.context.flatMap { $0.inlineOwner == nil ? $0.id : nil }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(s(.taskUITitle)).font(.largeTitle.bold())
                Spacer()
                if model.categories != nil {
                    Button(s(.taskCategoryUIManage),systemImage:"tag") { _ = model.beginCategories() }.disabled(model.busy || model.dialog != nil || model.creation?.context != nil)
                }
                if model.creation != nil {
                    Button(s(.taskCreateTitle), systemImage: "plus") { _ = model.beginCreate() }.disabled(model.busy || model.dialog != nil || model.creation?.context != nil)
                }
                if model.store.list.isLoading { ProgressView().controlSize(.small) }
                Button(s(.taskUIRefresh), systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                    .keyboardShortcut("r", modifiers: .command).disabled(model.busy)
            }
            filters
            if let bulk = model.bulk {
                TaskBulkToolbar(screen:model,model:bulk,visibleIDs:TaskPresentation.rows(model.store.list.value ?? [],query:model.query,status:model.status,category:model.categoryFilter,sort:model.sort,ascending:model.ascending,now:Int64(Date().timeIntervalSince1970)).map(\.id))
                if bulk.context == nil { TaskBulkSummary(model:bulk) }
                if let failure = bulk.failure { Text(failure.text(language:language)).foregroundStyle(.red) }
                if !bulk.uncertainIDs.isEmpty, bulk.context == nil {
                    Text(s(.taskBulkUnknown)).foregroundStyle(.orange)
                    Button(s(.taskBulkUnlock)) { bulk.requestAcknowledgement() }.disabled(model.busy || model.dialog != nil || model.creation?.context != nil)
                }
            }
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
        .sheet(item: model.categories.map { TaskCategoryBindings.presentation(model:$0,contextID:categoryID) } ?? .constant(nil)) { owner in
            if let workspace = model.categories { TaskCategoryView(model:workspace,contextID:owner.id) }
        }
        .sheet(item:model.bulk.map { TaskBulkBindings.presentation(model:$0,contextID:bulkID) } ?? .constant(nil)) { owner in
            if let bulk = model.bulk { TaskBulkView(model:bulk,contextID:owner.id) }
        }
        .alert(s(.taskBulkUnlockTitle),isPresented:Binding(get:{model.bulk?.acknowledgement != nil},set:{if !$0, let ackID { model.bulk?.resolveAcknowledgement(id:ackID,accept:false) }})) {
            Button(s(.taskUICancel),role:.cancel) { if let ackID { model.bulk?.resolveAcknowledgement(id:ackID,accept:false) } }
            Button(s(.taskBulkConfirm)) { if let ackID { model.bulk?.resolveAcknowledgement(id:ackID,accept:true) } }
        } message: {
            Text(s(.taskBulkUnlockHelp) + "\n" + (ack?.ids.sorted().prefix(30).map { "#"+$0 }.joined(separator:", ") ?? ""))
        }
        .onChange(of:model.store.list.value?.map(\.id)) { _,_ in model.bulk?.reconcileSelection() }
        .task { await model.categories?.refreshCatalog() }
        .task {
            if let id = requestedID {
                requestedID = nil; model.query = ""; model.status = nil; model.categoryFilter = .all
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
            if let workspace = model.categories {
                Picker(s(.taskUICategory),selection:Binding(get:{model.categoryFilter},set:{model.categoryFilter = $0})) {
                    Text(s(.taskUIAll)).tag(TaskCategoryFilter.all)
                    Text(s(.taskUIUncategorized)).tag(TaskCategoryFilter.uncategorized)
                    ForEach(workspace.categories) { Text($0.name).tag(TaskCategoryFilter.category($0.id)) }
                }.frame(maxWidth:180)
            }
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
            let rows = TaskPresentation.rows(model.store.list.value ?? [], query: model.query, status: model.status, category:model.categoryFilter,
                                             sort: model.sort, ascending: model.ascending, now: Int64(context.date.timeIntervalSince1970))
            let selectionOwner = model.bulk?.viewOwner
            Table(rows, selection: Binding(get: { model.store.selectedID }, set: { model.select($0) })) {
                if let owner = selectionOwner {
                    TableColumn(s(.taskBulkCheckbox)) { item in
                        Toggle(AppStrings.formatted(.taskBulkSelectTask,language:language,values:["id":item.id]),isOn:TaskBulkBindings.selected(screen:model,id:item.id,owner:owner)).labelsHidden().toggleStyle(.checkbox)
                    }.width(44)
                }
                TableColumn(s(.taskUIName)) { item in
                    HStack {
                        if item.pinned { Image(systemName: "pin.fill").accessibilityLabel(s(.taskUIPin)) }
                        VStack(alignment: .leading) {
                            Text(item.name.isEmpty ? AppStrings.formatted(.taskUIUnnamed, language: language, values: ["id": item.id]) : item.name).lineLimit(1)
                            Text(item.id).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.width(min: 130, ideal: 180)
                TableColumn(s(.taskUICategory)) { item in Text(item.categoryName ?? s(.taskUIUncategorized)).lineLimit(1) }.width(min:70,ideal:100)
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
