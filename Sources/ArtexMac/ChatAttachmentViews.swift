import ArtexCore
import SwiftUI

struct ChatAttachmentStrip: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }

    let attachments: [ChatAttachment]
    var remove: ((String) -> Void)? = nil
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 6)], alignment: .leading, spacing: 6) {
            if remove != nil {
                ForEach(attachments) { card($0) }
            } else {
                // Persisted messages may repeat a reference; preserve wire order.
                ForEach(Array(attachments.enumerated()), id: \.offset) { card($0.element) }
            }
        }
    }
    private func card(_ file: ChatAttachment) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "paperclip").foregroundStyle(.tint).accessibilityHidden(true)
            Text(file.name).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            Text(ChatAttachmentPresentation.bytes(file.size)).foregroundStyle(.secondary).fixedSize()
            if let remove {
                Button { remove(file.path) } label: {
                    Image(systemName: "xmark").frame(minWidth: 24, minHeight: 24).contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(s(.chatRemoveAttachmentPrefix) + file.name)
                .help(s(.chatRemoveAttachmentHelp))
            }
        }
        .font(.caption).padding(.leading, 8).padding(.trailing, 2).padding(.vertical, 3)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .help(file.path).accessibilityElement(children: .contain)
    }
}

struct ChatAttachmentProgressView: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }

    let presentation: ChatUploadPresentation
    let cancel: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(presentation.title)
                    Spacer()
                    if let detail = presentation.detail { Text(detail).foregroundStyle(.secondary).monospacedDigit() }
                }.font(.caption)
                if let fraction = presentation.fraction {
                    ProgressView(value: fraction).accessibilityLabel(presentation.title)
                } else {
                    ProgressView().controlSize(.small).accessibilityLabel(presentation.title)
                }
            }
            Button(s(.chatCancelUpload), action: cancel).controlSize(.small)
        }
        .accessibilityElement(children: .contain)
    }
}
