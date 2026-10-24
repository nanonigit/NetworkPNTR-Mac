import ArtexCore
import SwiftUI

struct ChatUserMessageView: View {
    let workspace: ChatWorkspace
    let conversationID: Int64
    let activity: ChatActivity
    @State private var model: ChatUserBodyStore
    @State private var retry = 0
    private struct LoadID: Hashable { let body: ChatUserBodyKey; let retry: Int }
    init(workspace: ChatWorkspace, conversationID: Int64, activity: ChatActivity) {
        self.workspace = workspace; self.conversationID = conversationID; self.activity = activity
        _model = State(initialValue: ChatUserBodyStore(summary: activity.summary, detail: activity.detail))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.body.attachments.isEmpty { ChatAttachmentStrip(attachments: model.body.attachments) }
            if !model.body.text.isEmpty {
                // The pinned user bubble is literal text, not Markdown or executable links.
                Text(model.body.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.isLoading { ProgressView("本文を読み込み中…").controlSize(.small) }
            if let error = model.error {
                HStack {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    Button("再試行") { retry += 1 }.accessibilityLabel("メッセージ本文を再読み込み")
                }.font(.caption)
            }
        }
        .task(id: LoadID(body: ChatUserBodyKey(conversationID: conversationID, activity: activity), retry: retry)) {
            await model.load(conversationID: conversationID, activity: activity, detail: workspace.detail)
        }
        .onDisappear { model.stop() }
    }
}
