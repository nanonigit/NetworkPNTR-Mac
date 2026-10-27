import ArtexCore
import SwiftUI

@MainActor struct FindingDialogView: View {
    let model: FindingScreenModel
    let contextID: UUID
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in:[locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key,language:language) }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            if let context = model.dialog, context.id == contextID {
                switch context.kind {
                case .edit(let row):
                    Text(s(.findingUIEdit)).font(.title2.bold())
                    Text("#"+row.id).foregroundStyle(.secondary)
                    Form {
                        TextField(s(.findingUIName),text:draft(\.nameDraft))
                        TextField(s(.findingUIClass),text:draft(\.classDraft))
                        Picker(s(.findingUISeverity),selection:FindingBindings.severity(model,id:contextID)) {
                            if FindingSeverity(rawValue:row.severity) == nil { Text(row.severity).tag("keep") }
                            ForEach(FindingSeverity.allCases,id:\.rawValue) { Text(DashboardLabels.text($0.rawValue,domain:.severity,language:language)).tag($0.rawValue) }
                        }
                    }.disabled(!writable)
                case .status(let row,let status):
                    Text(s(.findingUIStatus)).font(.title2.bold()); Text(row.name).textSelection(.enabled)
                    Text(FindingPresentation.status(row.status,language:language)+" → "+FindingPresentation.status(status.rawValue,language:language))
                case .delete(let row):
                    Text(s(.findingUIDelete)).font(.title2.bold()); Text(row.name).textSelection(.enabled); Text(s(.findingUIDeleteHelp))
                case .acknowledge(let id):
                    Text(s(.findingUIAcknowledge)).font(.title2.bold())
                    Text(AppStrings.formatted(.findingUIUnknown,language:language,values:["id":id])); Text(s(.findingUIUnknownHelp))
                }
                if let failure = model.dialogFailure { Text(failure.text(language:language)).foregroundStyle(.red) }
                if model.dialogUncertain { Text(s(.findingUIUnknownHelp)).foregroundStyle(.orange) }
                HStack {
                    Button(s(.findingUICancel),role:.cancel) { model.close(dialogID:contextID) }.keyboardShortcut(.cancelAction).disabled(model.busy)
                    Spacer()
                    if model.busy { ProgressView().controlSize(.small) }
                    Button(s(.findingUIConfirm)) { Task { _ = await model.submit(dialogID:contextID) } }.keyboardShortcut(.defaultAction).disabled(model.busy || model.dialogUncertain)
                }
            }
        }.padding(24).frame(minWidth:440,idealWidth:520)
        .interactiveDismissDisabled(model.busy)
    }
    private var writable: Bool { model.dialog?.id == contextID && !model.busy && !model.dialogUncertain }
    private func draft(_ key: ReferenceWritableKeyPath<FindingScreenModel,String>) -> Binding<String> {
        FindingBindings.draft(model,id:contextID,key:key)
    }
}
