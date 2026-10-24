import ArtexCore
import SwiftUI

struct ChatTranscriptView: View {
    let workspace: ChatWorkspace
    @State private var atBottom = true
    @State private var visibleAnchor: Int64?
    @State private var olderAnchor: Int64?
    @State private var detail: ChatActivity?
    private var store: ChatStore { workspace.transcript }
    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if let error = store.transcriptError {
                    HStack { Text(error).foregroundStyle(.red); Button("再試行") { Task { await workspace.select(store.selectedID); await store.refreshDelta() } } }
                        .font(.callout).padding(10)
                }
                if store.isLoadingHistory { ProgressView("履歴を読み込み中").padding() }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if store.hasMore {
                            Button(store.isLoadingOlder ? "読み込み中…" : "以前のメッセージを読み込む") {
                                olderAnchor = store.messages.first?.seq
                                Task { await store.loadOlder(); if store.transcriptError != nil { olderAnchor = nil } }
                            }.disabled(store.isLoadingOlder).frame(maxWidth: .infinity)
                        }
                        if store.messages.isEmpty, !store.isLoadingHistory {
                            ContentUnavailableView(store.selectedID == nil ? "新しい会話" : "メッセージはまだありません",
                                systemImage: "bubble.left.and.bubble.right", description: Text("エージェントとモデルを選び、メッセージを入力してください。"))
                                .frame(maxWidth: .infinity, minHeight: 220)
                        }
                        ForEach(store.messages) { event in eventRow(event).id(event.seq) }
                        Color.clear.frame(height: 1).id("chat-bottom")
                    }.scrollTargetLayout().padding(20)
                }
                .scrollPosition(id: $visibleAnchor, anchor: .top)
                .onChange(of: store.messages.first?.seq) { _, _ in
                    if let anchor = olderAnchor { proxy.scrollTo(anchor, anchor: .top); visibleAnchor = anchor; olderAnchor = nil }
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 72
                } action: { _, value in atBottom = value }
                .onChange(of: store.messages.last?.seq) { _, _ in if atBottom { proxy.scrollTo("chat-bottom", anchor: .bottom) } }
                .onChange(of: store.selectedID) { _, _ in atBottom = true; olderAnchor = nil; visibleAnchor = nil }
                if !atBottom { Button("最新のメッセージへ") { proxy.scrollTo("chat-bottom", anchor: .bottom) }.padding(6) }
            }
        }
        .sheet(item: $detail) { event in ChatDetailView(workspace: workspace, conversationID: store.selectedID, event: event) }
        .environment(\.openURL, OpenURLAction { url in ["https", "http"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded })
    }
    private func eventRow(_ event: ChatActivity) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(event.kind == "user" ? "あなた" : event.worker, systemImage: event.kind == "user" ? "person.crop.circle" : "sparkle")
                    .font(.caption.bold())
                Text(event.kind).font(.caption.monospaced()).foregroundStyle(event.isError == true ? .red : .secondary)
                if let tool = event.tool { Text(tool).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if let date = ISO8601DateFormatter().date(from: event.ts) { Text(date, format: .dateTime.month().day().hour().minute()).font(.caption2).foregroundStyle(.secondary) }
                Button("詳細") { detail = event }.font(.caption).help("イベントの詳細を取得")
            }
            if event.kind == "user", let owner = store.selectedID {
                ChatUserMessageView(workspace: workspace, conversationID: owner, activity: event)
                    .id(ChatUserBodyKey(conversationID: owner, activity: event))
            } else {
                Text((try? AttributedString(markdown: event.summary, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(event.summary))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let pair = event.toolUseId { Text("Call: " + pair).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled) }
            if let input = event.inputTokens, input > 0 {
                Text("入力 \(input) · 出力 \(event.outputTokens ?? 0) tokens").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(14).background(event.kind == "user" ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .contain)
    }
}
private struct ChatDetailView: View {
    let workspace: ChatWorkspace
    let conversationID: Int64?
    let event: ChatActivity
    @Environment(\.dismiss) private var dismiss
    @State private var text: String?
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("イベント詳細 · \(event.kind)").font(.headline); Spacer(); Button("閉じる") { dismiss() }.keyboardShortcut(.cancelAction) }
            if let error { Text(error).foregroundStyle(.red) }
            else if let text { ScrollView { Text(text.isEmpty ? "詳細はありません" : text).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) } }
            else { ProgressView("詳細を読み込み中") }
        }.padding(24).frame(minWidth: 560, minHeight: 380)
        .task {
            guard let id = conversationID else { return }
            do { text = try await workspace.detail(id: id, sequence: event.seq) }
            catch { self.error = (error as? BackendAPIError)?.localizedDescription ?? "詳細を取得できませんでした。" }
        }
    }
}
