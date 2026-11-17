import NetworkPNTRCore
import SwiftUI

@MainActor struct TaskCreateAttachments: View {
    let model: TaskCreationModel
    let contextID: UUID
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    var body: some View {
        if model.context?.id == contextID {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    ChatAttachmentPickerButton(enabled: model.uploadsAvailable && !model.isPicking && !model.isUploading && !model.isSubmitting && !model.uncertain && model.pendingTemplate == nil,
                        onChoose: { files in
                            let capturedLanguage = language
                            Task {
                                do { _ = try await TaskCreationUploadSelection.upload(files, contextID: contextID, language: capturedLanguage, model: model) }
                                catch is CancellationError { }
                                catch { model.pickerFailed(contextID: contextID) }
                            }
                        },
                        onPresentation: { model.setPickerPresented($0, contextID: contextID) },
                        onError: { model.pickerFailed(contextID: contextID) }, messageKey: .taskUploadPickerMessage)
                        .fixedSize()
                    Text(model.uploadCount == 0 ? s(.taskUploadIdle) : AppStrings.formatted(.taskUploadCount, language: language, values: ["count": String(model.uploadCount)]))
                        .foregroundStyle(.secondary)
                }
                Text(s(.taskUploadHelp)).font(.caption).foregroundStyle(.secondary)
                if model.isUploading {
                    let presentation = ChatUploadPresentation(progress: model.uploadProgress, language: language)
                    ProgressView(presentation.title, value: presentation.fraction)
                    if let progress = model.uploadProgress, presentation.fraction != nil {
                        Text(AppStrings.formatted(.taskUploadProgress, language: language, values: ["sent": String(progress.sentBodyBytes), "total": String(progress.totalBodyBytes)]))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let failure = model.uploadFailure { Text(failure.text(language: language)).font(.caption).foregroundStyle(.red) }
            }
        }
    }
}
