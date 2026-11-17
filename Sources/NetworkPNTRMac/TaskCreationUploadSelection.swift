import NetworkPNTRCore
import Foundation

@MainActor enum TaskCreationUploadSelection {
    static func upload(_ files: [URL], contextID: UUID, language: AppLanguage, model: TaskCreationModel,
                       access: ChatFileAccess = ChatFileAccess()) async throws -> Bool {
        guard model.context?.id == contextID, model.uploadsAvailable, !files.isEmpty, !Task.isCancelled,
              !model.isSubmitting, !model.isUploading, !model.isPicking, !model.uncertain, model.pendingTemplate == nil else { return false }
        return try await access.withAccess(files) {
            guard model.context?.id == contextID, !Task.isCancelled else { return false }
            return await model.uploadFiles(files, language: language, contextID: contextID)
        }
    }
}
