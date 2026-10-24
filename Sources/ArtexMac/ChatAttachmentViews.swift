import ArtexCore
import SwiftUI

struct ChatAttachmentStrip: View {
    let attachments: [ChatAttachment]
    let remove: (String) -> Void
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(attachments) { file in
                HStack(spacing: 6) {
                    Image(systemName: "paperclip").foregroundStyle(.tint).accessibilityHidden(true)
                    Text(file.name).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                    Text(ChatAttachmentPresentation.bytes(file.size)).foregroundStyle(.secondary).fixedSize()
                    Button { remove(file.path) } label: {
                        Image(systemName: "xmark").frame(minWidth: 24, minHeight: 24).contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("添付を外す：" + file.name)
                    .help("このメッセージの添付から外す")
                }
                .font(.caption).padding(.leading, 8).padding(.trailing, 2).padding(.vertical, 3)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .help(file.path).accessibilityElement(children: .contain)
            }
        }
    }
}

struct ChatAttachmentProgressView: View {
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
            Button("アップロードを取消", action: cancel).controlSize(.small)
        }
        .accessibilityElement(children: .contain)
    }
}
