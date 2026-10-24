import ArtexCore
import Foundation

struct ChatComposerAvailability {
    var draft: String
    var attachmentCount: Int
    var isNewConversation: Bool
    var hasAgent: Bool
    var historyReady: Bool
    var busy: Bool
    var sending: Bool
    var running: Bool
    var uploading: Bool
    var picking: Bool
    private var ready: Bool {
        !busy && !sending && !running && !uploading && !picking &&
        (isNewConversation ? hasAgent : historyReady)
    }
    var canSend: Bool { ready && (!ChatText.trim(draft).isEmpty || attachmentCount > 0) }
    var canPick: Bool { ready }
    var editorDisabled: Bool { busy || sending || running || (isNewConversation && uploading) }
}

enum ChatAttachmentPresentation {
    static func bytes(_ value: Int64) -> String {
        let unit: Int64 = value >= 1 << 20 ? 1 << 20 : value >= 1 << 10 ? 1 << 10 : 1
        guard unit > 1 else { return "\(value) B" }
        // Positive .toFixed(1) ties round up in the pinned JavaScript formatter.
        let tenths = (value / unit) * 10 + ((value % unit) * 10 + unit / 2) / unit
        return "\(tenths / 10).\(tenths % 10) \(unit == 1024 ? "KB" : "MB")"
    }
}

struct ChatUploadPresentation {
    let fraction: Double?
    let title: String
    let detail: String?
    init(progress: BackendUploadProgress?, language: AppLanguage = .japanese) {
        guard let progress, progress.totalBodyBytes > 0, progress.sentBodyBytes >= 0,
              progress.sentBodyBytes <= progress.totalBodyBytes else {
            fraction = nil; title = AppStrings.text(.chatPreparingFiles, language: language); detail = nil; return
        }
        fraction = Double(progress.sentBodyBytes) / Double(progress.totalBodyBytes)
        title = AppStrings.text(progress.sentBodyBytes == progress.totalBodyBytes ? .chatProcessingFiles : .chatUploading, language: language)
        detail = ChatAttachmentPresentation.bytes(progress.sentBodyBytes) + " / " + ChatAttachmentPresentation.bytes(progress.totalBodyBytes)
    }
}
