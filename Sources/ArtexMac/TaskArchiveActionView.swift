import ArtexCore
import SwiftUI

@MainActor enum TaskArchiveBindings {
    static func selected(screen: TaskScreenModel, id: Int64, owner: UUID) -> Binding<Bool> {
        Binding(get:{screen.archives?.viewOwner == owner && screen.archives?.selectedIDs.contains(id) == true},set:{screen.setArchiveSelected(id,selected:$0,owner:owner)})
    }
    static func presentation(model: TaskArchiveWorkspace, contextID: UUID?) -> Binding<TaskArchiveActionContext?> {
        Binding(get:{model.context},set:{if $0 == nil, let contextID { model.close(contextID:contextID) }})
    }
}

@MainActor struct TaskArchiveActionView: View {
    let model: TaskArchiveWorkspace
    let contextID: UUID
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in:[locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key,language:language) }
    private func f(_ key: AppStringKey,_ values: [String:String]) -> String { AppStrings.formatted(key,language:language,values:values) }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            if let context = model.context, context.id == contextID {
                Text(s(TaskArchivePresentation.actionKey(context.kind))).font(.title2.bold())
                Text(f(.taskArchiveUISelected,["count":String(context.resultIDs.count)])).font(.headline)
                ScrollView {
                    VStack(alignment:.leading,spacing:10) {
                        if !model.hasSubmitted {
                            Text(s(TaskArchivePresentation.helpKey(context.kind)))
                            if context.kind == .delete {
                                Text(f(.taskArchiveUIDeleteTotals,["rows":TaskArchivePresentation.number(TaskArchivePresentation.dataTotal(context.archives),language:language),"size":TaskArchivePresentation.bytes(TaskArchivePresentation.compressedTotal(context.archives),language:language)]))
                            }
                            ForEach(context.tasks) { row in Text("#"+row.id+" · "+row.name).textSelection(.enabled) }
                            ForEach(context.archives) { row in Text("#"+String(row.taskId)+" · "+TaskArchivePresentation.title(row,language:language)).textSelection(.enabled) }
                        } else {
                            TaskArchiveResultSummary(model:model)
                            ForEach(model.items) { row in
                                HStack(alignment:.top) {
                                    Text("#"+row.id).font(.caption.monospaced())
                                    Text(s(TaskArchivePresentation.outcomeKey(row.state)))
                                    if let error = row.failure { Text(error.text(language:language)).foregroundStyle(.secondary) }
                                }.textSelection(.enabled)
                            }
                        }
                        if let failure = model.failure { Text(failure.text(language:language)).foregroundStyle(.red) }
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }
                Divider()
                HStack {
                    if model.isSubmitting { ProgressView().controlSize(.small) }
                    Spacer()
                    Button(s(model.isSubmitting ? .taskBulkStop : .taskUIClose)) {
                        if model.isSubmitting { model.cancel(contextID:contextID) } else { model.close(contextID:contextID) }
                    }.keyboardShortcut(.cancelAction)
                    if !model.hasSubmitted {
                        Button(s(TaskArchivePresentation.actionKey(context.kind)),role:context.kind == .delete ? .destructive : nil) { model.submitFromUI(contextID:contextID) }
                            .keyboardShortcut(.defaultAction).disabled(model.isSubmitting)
                    }
                }
            }
        }.padding(24).frame(width:620,height:600).interactiveDismissDisabled(model.isSubmitting)
    }
}

@MainActor struct TaskArchiveResultSummary: View {
    let model: TaskArchiveWorkspace
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in:[locale.identifier]) }
    var body: some View {
        if !model.items.isEmpty {
            VStack(alignment:.leading,spacing:5) {
                Text(AppStrings.formatted(.taskArchiveUISummary,language:language,values:["ok":String(model.items.filter{$0.state == .accepted}.count),"failed":String(model.items.filter{$0.state == .rejected}.count),"unknown":String(model.items.filter{$0.state == .unconfirmed}.count),"pending":String(model.items.filter{$0.state == .notStarted}.count)]))
                if model.items.contains(where:{$0.state == .accepted}) { Text(AppStrings.text(.taskArchiveUIQueuedNotice,language:language)).font(.caption).foregroundStyle(.secondary) }
            }.textSelection(.enabled)
        }
    }
}

@MainActor struct TaskArchiveNotice: View {
    let screen: TaskScreenModel
    let model: TaskArchiveWorkspace
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in:[locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key,language:language) }
    var body: some View {
        let choice = model.acknowledgement
        let choiceID = choice?.id
        VStack(alignment:.leading,spacing:5) {
            if model.context == nil { TaskArchiveResultSummary(model:model) }
            if let failure = model.failure, model.context == nil { Text(failure.text(language:language)).foregroundStyle(.red) }
            if !model.uncertainTaskIDs.isEmpty || !model.uncertainArchiveIDs.isEmpty {
                Text(s(.taskArchiveUIUnknownHelp)).foregroundStyle(.orange)
                Button(s(.taskArchiveUIUnknownButton)) { model.requestAcknowledgement() }
                    .disabled(screen.busy || screen.dialog != nil || screen.creation?.context != nil)
            }
        }
        .alert(s(.taskArchiveUIUnknownButton),isPresented:Binding(get:{model.acknowledgement != nil},set:{if !$0, let choiceID { model.resolveAcknowledgement(id:choiceID,accept:false) }})) {
            Button(s(.taskUICancel),role:.cancel) { if let choiceID { model.resolveAcknowledgement(id:choiceID,accept:false) } }
            Button(s(.taskArchiveUIUnknownConfirm)) { if let choiceID { model.resolveAcknowledgement(id:choiceID,accept:true) } }
        } message: {
            Text(s(.taskArchiveUIUnknownHelp)+"\n"+AppStrings.formatted(.taskArchiveUIUnknownIDs,language:language,values:["tasks":choice?.taskIDs.sorted().prefix(100).joined(separator:", ") ?? "","archives":choice?.archiveIDs.sorted().prefix(100).map(String.init).joined(separator:", ") ?? ""]))
        }
    }
}
