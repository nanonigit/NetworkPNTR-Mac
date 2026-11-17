import NetworkPNTRCore
import SwiftUI

@MainActor struct TaskArchivePanel: View {
    let screen: TaskScreenModel
    let model: TaskArchiveStore
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in:[locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key,language:language) }
    private func f(_ key: AppStringKey,_ values: [String:String]) -> String { AppStrings.formatted(key,language:language,values:values) }
    private var rows: [TaskArchiveRecord] { model.list.value?.items ?? [] }
    private var blocked: Bool { screen.busy || screen.dialog != nil || screen.creation?.context != nil }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            filters
            selectionBar
            if let failure = model.list.failure { Text(failure.text(language:language)).foregroundStyle(.red).textSelection(.enabled) }
            if let failure = model.reconciliationFailure { Text(failure.text(language:language)).foregroundStyle(.red) }
            if model.list.isStale, model.list.value != nil { Text(s(.taskUIStale)).font(.caption).foregroundStyle(.secondary) }
            archiveTable
            pagination
        }
    }
    private var filters: some View {
        let owner = model.viewOwner
        return HStack(alignment:.bottom) {
            VStack(alignment:.leading,spacing:4) {
                Text(s(.taskArchiveUISearch)).font(.caption)
                HStack {
                    TextField(s(.taskArchiveUISearch),text:Binding(get:{screen.archiveQueryDraft},set:{screen.setArchiveDraft($0,owner:owner)}))
                        .textFieldStyle(.roundedBorder).accessibilityLabel(s(.taskArchiveUISearch))
                        .onSubmit { configure(page:1,size:model.size,query:screen.archiveQueryDraft,state:model.state,owner:owner) }
                    Button(s(.taskArchiveUISearch),systemImage:"magnifyingglass") { configure(page:1,size:model.size,query:screen.archiveQueryDraft,state:model.state,owner:owner) }.labelStyle(.iconOnly)
                }
            }.frame(maxWidth:420)
            Picker(s(.taskArchiveUIState),selection:Binding(get:{model.state ?? "all"},set:{configure(page:1,size:model.size,query:model.query,state:$0 == "all" ? nil : $0,owner:owner)})) {
                Text(s(.taskUIAll)).tag("all")
                ForEach(TaskArchiveSemantics.states,id:\.self) { value in Text(s(TaskArchiveSemantics.stateKey(value))).tag(value) }
            }.frame(maxWidth:250)
            Spacer()
            Text(f(.taskArchiveUITotal,["count":String(model.list.value?.total ?? 0)])).monospacedDigit()
            if model.list.isLoading { ProgressView().controlSize(.small) }
        }.disabled(blocked)
    }
    private var selectionBar: some View {
        let owner = model.viewOwner
        let selectable = rows.filter{!TaskArchiveSemantics.processing($0.state)}
        let count = selectable.filter{model.selectedIDs.contains($0.id)}.count
        let all = !selectable.isEmpty && count == selectable.count
        let selected = rows.filter{model.selectedIDs.contains($0.id)}
        return HStack {
            Button(s(.taskArchiveUISelectPage),systemImage:all ? "checkmark.square" : count > 0 ? "minus.square" : "square") { screen.selectArchivePage(selected:!all,owner:owner) }
                .accessibilityValue(s(all ? .taskBulkAll : count > 0 ? .taskBulkMixed : .taskBulkNone)).disabled(selectable.isEmpty)
            Text(f(.taskArchiveUISelected,["count":String(model.selectedIDs.count)])).monospacedDigit()
            Spacer()
            Button(s(.taskArchiveUIRestore),systemImage:"arrow.uturn.backward") { _ = screen.beginArchivedAction(.restore,records:selected) }
                .disabled(!selected.contains(where:TaskArchiveSemantics.canRestore))
            Button(s(.taskArchiveUIDelete),systemImage:"trash",role:.destructive) { _ = screen.beginArchivedAction(.delete,records:selected) }
                .disabled(!selected.contains(where:TaskArchiveSemantics.canDelete))
        }.controlSize(.small).disabled(blocked)
    }
    private var archiveTable: some View {
        let owner = model.viewOwner
        return Table(rows) {
            TableColumn("") { row in
                Toggle(f(.taskArchiveUISelectRow,["id":String(row.taskId)]),isOn:TaskArchiveBindings.selected(screen:screen,id:row.id,owner:owner))
                    .labelsHidden().toggleStyle(.checkbox).disabled(TaskArchiveSemantics.processing(row.state))
            }.width(36)
            TableColumn(s(.taskUIName)) { row in
                VStack(alignment:.leading,spacing:3) {
                    Text(TaskArchivePresentation.title(row,language:language)).lineLimit(2)
                    Text("#"+String(row.taskId)+" · "+row.taskDescription).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }.help(TaskArchivePresentation.title(row,language:language)+"\n"+row.taskDescription)
            }.width(min:160,ideal:210)
            TableColumn(s(.taskArchiveUIOriginalStatus)) { row in Text(TaskArchivePresentation.originalStatus(row,language:language)) }.width(min:80,ideal:100)
            TableColumn(s(.taskUICategory)) { row in Text(row.categoryName?.isEmpty == false ? row.categoryName! : s(.taskUIUncategorized)).lineLimit(1) }.width(min:80,ideal:110)
            TableColumn(s(.taskArchiveUIArchivedAt)) { row in Text(date(row.archivedAt ?? row.requestedAt)).font(.caption) }.width(min:110,ideal:140)
            TableColumn(s(.taskArchiveUICompressedSize)) { row in
                Text(TaskArchivePresentation.compression(row,language:language)).font(.caption)
                    .help(f(.taskArchiveUIOriginalSize,["size":TaskArchivePresentation.bytes(Decimal(row.originalSize),language:language)]))
            }.width(min:100,ideal:140)
            TableColumn(s(.taskArchiveUIDataCount)) { row in Text(TaskArchivePresentation.number(TaskArchivePresentation.dataTotal([row]),language:language)).font(.caption.monospacedDigit()) }.width(min:90,ideal:140)
            TableColumn(s(.taskArchiveUIProcessingState)) { row in stateCell(row) }.width(min:170,ideal:240)
            TableColumn(s(.taskArchiveUIActions)) { row in rowActions(row) }.width(min:90,ideal:110)
        }.disabled(blocked)
        .overlay {
            if model.list.value == nil, model.list.isLoading { ProgressView(s(.taskUILoading)) }
            else if model.list.value != nil, rows.isEmpty {
                VStack(spacing:8) {
                    Image(systemName:"archivebox").font(.largeTitle).foregroundStyle(.secondary)
                    Text(s(.taskArchiveUIEmpty)).font(.headline)
                    Text(s(model.query.isEmpty && model.state == nil ? .taskArchiveUIEmptyHelp : .taskArchiveUINoMatch)).foregroundStyle(.secondary)
                }.padding()
            }
        }
    }
    private func stateCell(_ row: TaskArchiveRecord) -> some View {
        VStack(alignment:.leading,spacing:4) {
            Text(s(TaskArchiveSemantics.stateKey(row.state))).font(.caption.bold())
            if TaskArchiveSemantics.processing(row.state) { ProgressView(value:Double(row.progress),total:100).accessibilityLabel(s(.taskArchiveUIProcessingState)) }
            Text(f(.taskArchiveUIProgress,["phase":s(TaskArchiveSemantics.phaseKey(row.phase)),"percent":String(row.progress)])).font(.caption).foregroundStyle(.secondary)
            if row.hasError { Text(s(.taskArchiveUIWorkerError)).font(.caption).foregroundStyle(.red) }
            if row.warningCount > 0 { Text(f(.taskArchiveUIWarnings,["count":String(row.warningCount)])).font(.caption).foregroundStyle(.orange) }
        }.padding(.vertical,5)
    }
    private func rowActions(_ row: TaskArchiveRecord) -> some View {
        HStack(spacing:4) {
            if TaskArchiveSemantics.canRetry(row) { action(.retry,row:row,icon:"arrow.clockwise") }
            if TaskArchiveSemantics.canRestore(row) { action(.restore,row:row,icon:"arrow.uturn.backward") }
            if TaskArchiveSemantics.canDelete(row) { action(.delete,row:row,icon:"trash") }
        }.controlSize(.small)
    }
    private func action(_ kind: TaskArchiveActionKind, row: TaskArchiveRecord, icon: String) -> some View {
        let label = f(.taskArchiveUIRowAction,["action":s(TaskArchivePresentation.actionKey(kind)),"id":String(row.taskId)])
        return Button(label,systemImage:icon,role:kind == .delete ? .destructive : nil) { _ = screen.beginArchivedAction(kind,records:[row]) }
            .labelStyle(.iconOnly).accessibilityLabel(label).help(label)
    }
    private var pagination: some View {
        let owner = model.viewOwner
        let pages = TaskArchivePresentation.pages(total:model.list.value?.total ?? 0,size:model.size)
        return HStack {
            Picker(s(.taskArchiveUIPageSize),selection:Binding(get:{model.size},set:{configure(page:1,size:$0,query:model.query,state:model.state,owner:owner)})) {
                ForEach([10,20,50],id:\.self) { Text(String($0)).tag($0) }
            }.frame(width:210)
            Spacer()
            Text(f(.taskArchiveUIPage,["page":String(model.page),"pages":String(pages)])).monospacedDigit()
            Button(s(.taskArchiveUIPrevious),systemImage:"chevron.left") { configure(page:model.page-1,size:model.size,query:model.query,state:model.state,owner:owner) }
                .labelStyle(.iconOnly).disabled(model.page <= 1)
            Button(s(.taskArchiveUINext),systemImage:"chevron.right") { configure(page:model.page+1,size:model.size,query:model.query,state:model.state,owner:owner) }
                .labelStyle(.iconOnly).disabled(model.page >= pages)
        }.disabled(blocked)
    }
    private func configure(page: Int64, size: Int, query: String, state: String?, owner: UUID) {
        guard screen.configureArchives(page:page,size:size,query:query,state:state,owner:owner) else { return }
        let nextOwner = model.viewOwner
        Task { guard model.viewOwner == nextOwner, screen.taskTab == .archived, !Task.isCancelled else { return }; await model.refresh() }
    }
    private func date(_ value: String) -> String {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
        let fractional = formatter.date(from:value); formatter.formatOptions = [.withInternetDateTime]
        guard let date = fractional ?? formatter.date(from:value) else { return "—" }
        return date.formatted(.dateTime.year().month().day().hour().minute().locale(locale))
    }
}
