import ArtexCore
import SwiftUI

@MainActor enum TaskBulkBindings {
    static func selected(screen: TaskScreenModel, id: String, owner: UUID) -> Binding<Bool> {
        Binding(get:{screen.bulk?.viewOwner == owner && screen.bulk?.selectedIDs.contains(id) == true},set:{screen.setBulkSelected(id,selected:$0,owner:owner)})
    }
    static func cleanup(model: TaskBulkWorkspace, contextID: UUID, key: WritableKeyPath<TaskDeletionOptions,Bool>) -> Binding<Bool> {
        Binding(get:{model.context?.id == contextID && model.options[keyPath:key]},set:{model.setOption(key,value:$0,contextID:contextID)})
    }
    static func presentation(model: TaskBulkWorkspace, contextID: UUID?) -> Binding<TaskBulkContext?> {
        Binding(get:{model.context},set:{if $0 == nil, let contextID { model.close(contextID:contextID) }})
    }
}

@MainActor struct TaskBulkView: View {
    let model: TaskBulkWorkspace
    let contextID: UUID
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in:[locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key,language:language) }
    private func f(_ key: AppStringKey,_ values: [String:String]) -> String { AppStrings.formatted(key,language:language,values:values) }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            if let context = model.context, context.id == contextID {
                Text(s(.taskBulkTitle)).font(.title2.bold())
                Text(f(.taskBulkSelected,["count":String(context.ids.count)])).font(.headline)
                Text(context.ids.prefix(30).map { "#"+$0 }.joined(separator:", ")).font(.caption.monospaced()).textSelection(.enabled)
                if context.ids.count > 30 { Text(f(.taskBulkMore,["count":String(context.ids.count-30)])).font(.caption) }
                if !model.hasSubmitted {
                    switch context.kind {
                    case .delete:
                        Text(s(.taskBulkDeleteHelp)); Text(s(.taskUIDeleteHelp)).foregroundStyle(.secondary)
                        Toggle(s(.taskUICleanupAssets),isOn:option(\.deleteAssets))
                        Toggle(s(.taskUICleanupTraffic),isOn:option(\.deleteTraffic))
                        Toggle(s(.taskUICleanupFiles),isOn:option(\.deleteFiles))
                        Toggle(s(.taskUICleanupFindings),isOn:option(\.deleteFindings))
                        Toggle(s(.taskUICleanupLLM),isOn:option(\.deleteLlmRecords))
                    case .control(let action): Text(s(action == .pause ? .taskBulkPauseHelp : .taskBulkResumeHelp))
                    case .move:
                        Picker(s(.taskCategoryUITarget),selection:Binding(get:{model.targetID},set:{model.setTarget($0,contextID:contextID)})) {
                            Text(s(.taskUIUncategorized)).tag(Optional<Int64>.none)
                            ForEach(model.categoryOptions) { Text($0.name).tag(Optional($0.id)) }
                            if let id = model.targetID, !model.categoryOptions.contains(where:{$0.id == id}) {
                                Text(AppStrings.formatted(.taskCreateUnavailable,language:language,values:["id":String(id)])).tag(Optional(id))
                            }
                        }
                    }
                }
                if let failure = model.failure { Text(failure.text(language:language)).foregroundStyle(.red) }
                if model.hasSubmitted {
                    Text(f(.taskBulkProgress,["done":String(model.completedCount),"total":String(context.ids.count)]))
                    TaskBulkSummary(model:model)
                    ScrollView {
                        VStack(alignment:.leading,spacing:8) {
                            ForEach(model.items) { row in
                                HStack(alignment:.top) {
                                    Text("#"+row.id).font(.caption.monospaced())
                                    Text(s(stateKey(row.state))).foregroundStyle(row.state == .succeeded ? Color.primary : .orange)
                                    if let error = row.failure { Text(error.text(language:language)).foregroundStyle(.secondary) }
                                }
                            }
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                }
                Spacer(minLength:0); Divider()
                HStack {
                    if model.isMutating { ProgressView().controlSize(.small) }
                    Spacer()
                    Button(s(model.isMutating ? .taskBulkStop : .taskUIClose)) {
                        if model.isMutating { model.cancelRemaining(contextID:contextID) } else { model.close(contextID:contextID) }
                    }.keyboardShortcut(.cancelAction)
                    if !model.hasSubmitted {
                        Button(s(context.kind == .delete ? .taskBulkDelete : .taskBulkConfirm),role:context.kind == .delete ? .destructive : nil) { model.submitFromUI(contextID:contextID) }
                            .keyboardShortcut(.defaultAction).disabled(model.isMutating)
                    }
                }
            }
        }.padding(24).frame(width:600,height:650).interactiveDismissDisabled(model.isMutating)
    }
    private func option(_ key: WritableKeyPath<TaskDeletionOptions,Bool>) -> Binding<Bool> { TaskBulkBindings.cleanup(model:model,contextID:contextID,key:key) }
    private func stateKey(_ state: TaskBulkItem.State) -> AppStringKey {
        switch state { case .succeeded: .taskBulkSucceeded; case .rejected: .taskBulkRejected; case .unconfirmed: .taskBulkUnconfirmed; case .notStarted: .taskBulkNotStarted }
    }
}

@MainActor struct TaskBulkSummary: View {
    let model: TaskBulkWorkspace
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in:[locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key,language:language) }
    private func decimal(_ value: Decimal) -> String { NSDecimalNumber(decimal:value).stringValue }
    var body: some View {
        VStack(alignment:.leading,spacing:4) {
            if !model.items.isEmpty {
                Text(AppStrings.formatted(.taskBulkSummary,language:language,values:["ok":String(model.items.filter{$0.state == .succeeded}.count),"failed":String(model.items.filter{$0.state == .rejected}.count),"unknown":String(model.items.filter{$0.state == .unconfirmed}.count),"pending":String(model.items.filter{$0.state == .notStarted}.count)]))
                if model.lastKind == .delete {
                    Text(AppStrings.formatted(.taskUICleanupCounts,language:language,values:["assets":model.totals.assetsText,"detached":decimal(model.totals.detached),"traffic":decimal(model.totals.traffic),"findings":decimal(model.totals.findings),"llm":decimal(model.totals.llm)])).font(.caption)
                    if model.totals.filesDeleted { Text(s(.taskUIFilesDeleted)).font(.caption) }
                    if !model.warningIDs.isEmpty { Text(s(.taskUICleanupWarning)).foregroundStyle(.orange) }
                }
                if !model.queuedIDs.isEmpty { Text(AppStrings.formatted(.taskBulkQueued,language:language,values:["count":String(model.queuedIDs.count)])).font(.caption) }
            }
        }.textSelection(.enabled)
    }
}

@MainActor struct TaskBulkToolbar: View {
    let screen: TaskScreenModel
    let model: TaskBulkWorkspace
    let visibleIDs: [String]
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in:[locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key,language:language) }
    var body: some View {
        let owner = model.viewOwner
        let count = visibleIDs.filter { model.selectedIDs.contains($0) }.count
        let all = !visibleIDs.isEmpty && count == visibleIDs.count
        HStack {
            Button(s(.taskBulkSelectVisible),systemImage:all ? "checkmark.square" : count > 0 ? "minus.square" : "square") {
                screen.setBulkVisible(visibleIDs,selected:!all,owner:owner)
            }.disabled(visibleIDs.isEmpty).accessibilityValue(s(all ? .taskBulkAll : count > 0 ? .taskBulkMixed : .taskBulkNone))
            Text(AppStrings.formatted(.taskBulkSelected,language:language,values:["count":String(model.selectedIDs.count)]))
            Button(s(.taskBulkClear)) { model.clearSelection(owner:owner) }.disabled(model.selectedIDs.isEmpty)
            Spacer()
            Button(s(.taskBulkPause)) { _ = screen.beginBulk(.control(.pause)) }.disabled(model.eligibleCount(.pause) == 0)
            Button(s(.taskBulkResume)) { _ = screen.beginBulk(.control(.resume)) }.disabled(model.eligibleCount(.resume) == 0)
            Button(s(.taskBulkMove)) { _ = screen.beginBulk(.move) }.disabled(!model.canMove || model.selectedIDs.isEmpty)
            Button(s(.taskBulkDelete),role:.destructive) { _ = screen.beginBulk(.delete) }.disabled(model.selectedIDs.isEmpty)
        }.controlSize(.small).disabled(screen.busy || screen.dialog != nil || screen.creation?.context != nil)
    }
}
