import ArtexCore
import SwiftUI

@MainActor struct FindingTrafficActionView: View {
    let actions: FindingTrafficActions
    let id: UUID
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in:[locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key,language:language) }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            if let context = actions.dialog, context.id == id {
                Text(title(context.kind)).font(.title2.bold())
                switch context.kind {
                case .edit(let binding):
                    Text(AppStrings.formatted(.evidenceUIBindingID,language:language,values:["id":binding])).foregroundStyle(.secondary)
                    Picker(s(.evidenceUIRole),selection:FindingTrafficActionBindings.role(actions,id:id)) {
                        Text(s(.evidenceUIChooseRole)).tag("")
                        ForEach(FindingTrafficRole.allCases,id:\.rawValue) { role in
                            Text(FindingTrafficPresentation.roleLabel(role.rawValue,language:language)).tag(role.rawValue)
                        }
                    }.disabled(actions.isSubmitting || actions.uncertain)
                    Text(s(.evidenceUINote)).font(.headline)
                    TextEditor(text:FindingTrafficActionBindings.note(actions,id:id)).font(.body).frame(minHeight:140).border(.secondary.opacity(0.3))
                        .disabled(actions.isSubmitting || actions.uncertain).accessibilityLabel(s(.evidenceUINote))
                case .remove(let binding):
                    Text(AppStrings.formatted(.evidenceUIRemoveHelp,language:language,values:["id":binding]))
                case .reorder(let ids):
                    Text(s(.evidenceUIOrderHelp))
                    Text(verbatim:ids.joined(separator:" → ")).font(.body.monospaced()).textSelection(.enabled)
                case .acknowledge:
                    Text(s(.evidenceUIUnknownHelp)).textSelection(.enabled)
                }
                if actions.uncertain { Text(s(.evidenceUIUnknownHelp)).foregroundStyle(.orange) }
                if let failure = actions.failure { Text(failure.text(language:language)).foregroundStyle(.red).textSelection(.enabled) }
                HStack {
                    if actions.isSubmitting { ProgressView().controlSize(.small) }
                    Spacer()
                    Button(s(.findingUICancel)) { actions.close(id:id) }.keyboardShortcut(.cancelAction).disabled(actions.isSubmitting)
                    Button(s(.findingUIConfirm)) { Task { _ = await actions.submit(id:id) } }
                        .keyboardShortcut(.defaultAction).disabled(!actions.canSubmit)
                }
            }
        }
        .padding(24).frame(minWidth:460,idealWidth:540,minHeight:220)
        .interactiveDismissDisabled(actions.isSubmitting)
    }
    private func title(_ kind: FindingTrafficActionDialog.Kind) -> String {
        switch kind {
        case .edit: s(.evidenceUIEdit)
        case .remove: s(.evidenceUIRemove)
        case .reorder: s(.evidenceUIReorder)
        case .acknowledge: s(.evidenceUIReviewUnknown)
        }
    }
}
