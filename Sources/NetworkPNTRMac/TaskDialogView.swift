import NetworkPNTRCore
import SwiftUI

@MainActor struct TaskDialogView: View {
    let model: TaskScreenModel
    let contextID: UUID
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let context = model.dialog, context.id == contextID {
                Text(s(context.kind == .rename ? .taskUIRename : .taskUIDeleteTitle)).font(.title2.bold())
                Text(context.task.name).font(.headline).textSelection(.enabled)
                Text(context.task.id).font(.caption.monospaced()).textSelection(.enabled)
                if context.kind == .rename {
                    TextField(s(.taskUIName), text: TaskDialogBindings.rename(model: model, dialogID: contextID))
                        .textFieldStyle(.roundedBorder).disabled(model.busy || model.dialogUncertain)
                } else {
                    Text(s(.taskUIDeleteHelp))
                    Toggle(s(.taskUICleanupAssets), isOn: option(\.deleteAssets)).disabled(model.busy || model.dialogUncertain)
                    Toggle(s(.taskUICleanupTraffic), isOn: option(\.deleteTraffic)).disabled(model.busy || model.dialogUncertain)
                    Toggle(s(.taskUICleanupFiles), isOn: option(\.deleteFiles)).disabled(model.busy || model.dialogUncertain)
                    Toggle(s(.taskUICleanupFindings), isOn: option(\.deleteFindings)).disabled(model.busy || model.dialogUncertain)
                    Toggle(s(.taskUICleanupLLM), isOn: option(\.deleteLlmRecords)).disabled(model.busy || model.dialogUncertain)
                }
                if model.dialogUncertain { Text(s(.taskUIUncertain)).foregroundStyle(.orange) }
                else if let failure = model.dialogFailure { Text(failure.text(language: language)).foregroundStyle(.red) }
                HStack {
                    if model.isSubmitting { ProgressView().controlSize(.small) }
                    Spacer()
                    Button(s(model.dialogUncertain ? .taskUIClose : .taskUICancel)) { model.closeDialog(id: context.id) }
                        .keyboardShortcut(.cancelAction).disabled(model.busy)
                    Button(s(context.kind == .rename ? .taskUISave : .taskUIDeleteConfirm), role: context.kind == .delete ? .destructive : nil) { Task { _ = await model.submit(dialogID: context.id) } }
                        .keyboardShortcut(.defaultAction).disabled(model.busy || model.dialogUncertain)
                }
            }
        }.padding(24).frame(width: 440).interactiveDismissDisabled(model.busy)
    }
    private func option(_ key: WritableKeyPath<TaskDeletionOptions, Bool>) -> Binding<Bool> {
        TaskDialogBindings.cleanup(model: model, dialogID: contextID, key: key)
    }
}

@MainActor struct TaskOperationNotice: View {
    let store: TaskStore
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if store.mutationUncertain { Text(s(.taskUIUncertain)).foregroundStyle(.orange) }
            else if let failure = store.mutationFailure { Text(failure.text(language: language)).foregroundStyle(.red) }
            if let receipt = store.lastConfirmation {
                switch receipt {
                case .deleted(let result):
                    Text(AppStrings.formatted(.taskUIDeleted, language: language, values: ["id": result.deleted]))
                    Text(AppStrings.formatted(.taskUICleanupCounts, language: language, values: ["assets": String(result.assetsDeleted), "detached": String(result.assetsDetached), "traffic": String(result.trafficDeleted), "findings": String(result.findingsDeleted), "llm": String(result.llmRecordsDeleted)])).font(.caption)
                    if result.filesDeleted { Text(s(.taskUIFilesDeleted)).font(.caption) }
                    if result.hasCleanupWarning { Text(s(.taskUICleanupWarning)).foregroundStyle(.orange) }
                case .created(let task): Text(AppStrings.formatted(.taskCreateCreated, language: language, values: ["id": task.id]))
                case .updated(let task): Text(AppStrings.formatted(.taskUIChanged, language: language, values: ["id": task.id]))
                case .controlled(let result): Text(AppStrings.formatted(.taskUIChanged, language: language, values: ["id": result.id]))
                case .batchControlled: EmptyView()
                }
            }
        }.font(.callout).textSelection(.enabled)
    }
}

/// Already-issued AppKit/IME callbacks must retain the dialog that created them.
@MainActor enum TaskDialogBindings {
    static func rename(model: TaskScreenModel, dialogID: UUID) -> Binding<String> {
        Binding(get: { model.dialog?.id == dialogID ? model.renameDraft : "" }, set: { value in
            guard model.dialog?.id == dialogID, !model.busy, !model.dialogUncertain else { return }
            model.renameDraft = value
        })
    }
    static func cleanup(model: TaskScreenModel, dialogID: UUID, key: WritableKeyPath<TaskDeletionOptions, Bool>) -> Binding<Bool> {
        Binding(get: { model.dialog?.id == dialogID && model.deletionOptions[keyPath: key] }, set: { value in
            guard model.dialog?.id == dialogID, !model.busy, !model.dialogUncertain else { return }
            model.deletionOptions[keyPath: key] = value
        })
    }
}
