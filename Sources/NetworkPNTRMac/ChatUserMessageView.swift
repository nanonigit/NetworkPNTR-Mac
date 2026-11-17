import NetworkPNTRCore
import SwiftUI

struct ChatUserMessageView: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }

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
            if model.isLoading { ProgressView(s(.chatLoadingBody)).controlSize(.small) }
            if let error = model.failure?.text(language: language) {
                HStack {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    Button(s(.chatRetry)) { retry += 1 }.accessibilityLabel(s(.chatReloadBody))
                }.font(.caption)
            }
        }
        .task(id: LoadID(body: ChatUserBodyKey(conversationID: conversationID, activity: activity), retry: retry)) {
            await model.load(conversationID: conversationID, activity: activity, detail: workspace.detail)
        }
        .onDisappear { model.stop() }
    }
}
