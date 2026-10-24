import ArtexCore
import SwiftUI

struct ChatView: View {
    @State private var workspace: ChatWorkspace
    @State private var pickingFiles = false
    @State private var pickerError: String?
    @State private var uploadTasks: [UUID: Task<Void, Never>] = [:]
    @State private var filter = ""
    @State private var visibleCount = 100
    @State private var batchMode = false
    @State private var checked: Set<Int64> = []
    @State private var deletion: [Int64] = []
    @State private var renameID: Int64?
    @State private var renameText = ""
    @FocusState private var renameFocus: Int64?
    @AppStorage("chat-send-mode") private var sendMode = "enter"
    @AppStorage("chat-collapsed-agent-keys") private var collapsedJSON = "[]"
    private var store: ChatStore { workspace.transcript }
    init(session: AuthenticationSession) { _workspace = State(initialValue: ChatWorkspace(client: AuthenticatedBackendClient(session: session))) }
    private var filtered: [ChatConversation] { store.conversations.filter { filter.isEmpty || $0.agentKey == filter } }
    private var visible: [ChatConversation] { Array(filtered.prefix(visibleCount)) }
    private var keys: [String] {
        var seen: Set<String> = []
        return visible.filter { !$0.isPinned }.map(\.agentKey).filter { seen.insert($0).inserted }
    }
    private var collapsed: Set<String> { Set((try? JSONDecoder().decode([String].self, from: Data(collapsedJSON.utf8))) ?? []) }
    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Button { Task { await workspace.select(nil) } } label: { Label("新しい会話", systemImage: "plus").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                    Picker("エージェントで絞り込み", selection: $filter) {
                        Text("すべてのエージェント").tag("")
                        ForEach(Array(Set(store.conversations.map(\.agentKey) + workspace.agents.map(\.key))).sorted(), id: \.self) { key in Text(workspace.name(for: key)).tag(key) }
                    }.labelsHidden().accessibilityLabel("エージェントで絞り込み")
                    HStack {
                        Toggle("複数選択", isOn: $batchMode).toggleStyle(.button)
                        Spacer()
                        if batchMode { Button("削除 (\(checked.count))", role: .destructive) { deletion = Array(checked) }.disabled(checked.isEmpty || workspace.busy) }
                    }.font(.caption)
                }.padding(12)
                Divider()
                if let error = store.listError { Text(error).font(.caption).foregroundStyle(.red).padding(8) }
                List {
                    if !visible.filter(\.isPinned).isEmpty {
                        Section("ピン留め") { ForEach(visible.filter(\.isPinned)) { conversationRow($0) } }
                    }
                    ForEach(keys, id: \.self) { key in
                        DisclosureGroup(isExpanded: Binding(get: { !collapsed.contains(key) }, set: { expanded in
                            var values = collapsed; if expanded { values.remove(key) } else { values.insert(key) }
                            if let data = try? JSONEncoder().encode(values.sorted()), let value = String(data: data, encoding: .utf8) { collapsedJSON = value }
                        })) {
                            ForEach(visible.filter { !$0.isPinned && $0.agentKey == key }) { conversationRow($0) }
                        } label: { Text(workspace.name(for: key)).font(.caption.bold()) }
                    }
                    if filtered.count > visibleCount { Button("さらに100件を表示") { visibleCount += 100 } }
                    if store.conversations.isEmpty { Text(store.isLoadingList ? "読み込み中…" : "会話はまだありません").foregroundStyle(.secondary) }
                }.listStyle(.sidebar)
            }.frame(minWidth: 210, idealWidth: 250, maxWidth: 360)
            VStack(spacing: 0) {
                header.padding(14)
                Divider()
                ChatTranscriptView(workspace: workspace)
                Divider()
                composer.padding(14)
            }.frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Chat")
        .task { await workspace.load(); await store.pollList() }
        .task(id: store.selectedID) { await store.pollSelected() }
        .onDisappear {
            for task in uploadTasks.values { task.cancel() }
            uploadTasks.removeAll(); pickingFiles = false; workspace.stop()
        }
        .onChange(of: store.selectedID) { _, _ in pickingFiles = false; pickerError = nil }
        .onChange(of: filter) { _, _ in visibleCount = 100 }
        .onChange(of: batchMode) { _, active in if !active { checked = [] } }
        .confirmationDialog("選択した会話を削除しますか？", isPresented: Binding(get: { !deletion.isEmpty }, set: { if !$0 { deletion = [] } }), titleVisibility: .visible) {
            Button("会話を削除", role: .destructive) {
                let ids = deletion; deletion = []
                Task { let result = await workspace.delete(ids: ids); checked.subtract(result.filter(\.ok).map(\.id)) }
            }
            Button("キャンセル", role: .cancel) { deletion = [] }
        } message: { Text("会話と保存済みのメッセージを削除します。") }
    }
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(workspace.selected?.title ?? "新しい会話").font(.headline).lineLimit(1)
                if let selected = workspace.selected { Text(workspace.name(for: selected.agentKey)).font(.caption).foregroundStyle(.secondary) }
                else {
                    Picker("エージェント", selection: Binding(get: { workspace.agentKey }, set: { workspace.agentKey = $0 })) {
                        Text("選択してください").tag("")
                        ForEach(workspace.agents) { Text($0.name).tag($0.key) }
                    }.frame(maxWidth: 240)
                }
            }
            Spacer()
            Picker("モデル", selection: Binding<Int64?>(get: { store.selectedID == nil ? workspace.draftProfileID : workspace.selected?.llmProfileId }, set: { id in
                if let selected = store.selectedID { Task { await workspace.changeProfile(id: selected, profileID: id) } }
                else { workspace.draftProfileID = id }
            })) {
                Text("既定のモデル").tag(nil as Int64?)
                ForEach(workspace.profiles) { profile in if let id = Int64(profile.id) { Text(profile.name).tag(Optional(id)) } }
            }.frame(maxWidth: 250).disabled(workspace.busy || store.running)
        }
    }
    private var composerAvailability: ChatComposerAvailability {
        ChatComposerAvailability(draft: store.draft, attachmentCount: store.attachments.count,
            isNewConversation: store.selectedID == nil, hasAgent: !workspace.agentKey.isEmpty,
            historyReady: store.hasLoadedHistory && !store.isLoadingHistory,
            busy: workspace.busy, sending: store.isSending, running: store.running,
            uploading: workspace.isUploading, picking: pickingFiles)
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = pickerError ?? workspace.uploadError ?? workspace.error ?? store.mutationError {
                Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            if !store.attachments.isEmpty {
                attachmentStrip(owner: store.selectedID ?? 0)
            }
            if let upload = workspace.uploadState(for: store.selectedID) {
                uploadProgress(upload, owner: store.selectedID)
            }
            if let agent = workspace.agents.first(where: { $0.key == workspace.agentKey }), store.selectedID == nil {
                Text(agent.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            ChatMentionComposer(text: ChatComposer.draftBinding(store: store, conversationID: store.selectedID), service: workspace.mentionService, mode: sendMode, disabled: composerAvailability.editorDisabled, send: send)
                .id(store.selectedID ?? 0)
            HStack {
                attachmentPicker(owner: store.selectedID)
                Picker("送信キー", selection: $sendMode) { Text("Enterで送信").tag("enter"); Text("Ctrl / ⌘ + Enterで送信").tag("ctrl-enter") }
                    .labelsHidden().frame(maxWidth: 220).accessibilityLabel("送信キー")
                Spacer()
                if store.running {
                    Button(store.isStopping ? "停止要求中…" : "停止", role: .destructive) { Task { _ = await store.requestStop() } }.disabled(store.isStopping)
                } else {
                    Button { send() } label: { Label(store.isSending || workspace.busy ? "送信中…" : "送信", systemImage: "arrow.up") }
                        .buttonStyle(.borderedProminent)
                        .disabled(!composerAvailability.canSend)
                }
            }
        }
    }
    private func send() {
        guard composerAvailability.canSend else { return }
        Task { _ = await workspace.send() }
    }
    private func attachmentStrip(owner: Int64) -> some View {
        ChatAttachmentStrip(attachments: store.attachments(for: owner)) { path in
            store.removeAttachment(path: path, for: owner)
        }
    }
    private func uploadProgress(_ upload: ChatAttachmentUploadState, owner: Int64?) -> some View {
        ChatAttachmentProgressView(presentation: ChatUploadPresentation(progress: upload.progress)) {
            workspace.cancelUpload(for: owner, operationID: upload.operationID)
        }
    }
    private func attachmentPicker(owner: Int64?) -> some View {
        ChatAttachmentPickerButton(enabled: composerAvailability.canPick, onChoose: { files in
            guard owner == store.selectedID, !files.isEmpty else { return }
            pickerError = nil
            let id = UUID(), workspace = workspace
            uploadTasks[id] = Task { @MainActor in
                defer { uploadTasks.removeValue(forKey: id) }
                do {
                    _ = try await ChatAttachmentSelection.upload(files, owner: owner, workspace: workspace)
                } catch is CancellationError {
                    // Cancellation is a user action; the workspace invalidates its own operation.
                } catch {
                    if owner == store.selectedID { pickerError = "ファイルを読み取れませんでした。もう一度選択してください。" }
                }
            }
        }, onPresentation: { presented in
            if owner == store.selectedID { pickingFiles = presented; if presented { pickerError = nil } }
        }, onError: {
            if owner == store.selectedID { pickerError = "ファイル選択を開けませんでした。もう一度お試しください。" }
        })
        .id(owner ?? 0).frame(width: 128, height: 28)
    }
    private func conversationRow(_ conversation: ChatConversation) -> some View {
        HStack(spacing: 5) {
            if batchMode { Toggle("選択：" + conversation.title, isOn: Binding(get: { checked.contains(conversation.id) }, set: { value in if value { checked.insert(conversation.id) } else { checked.remove(conversation.id) } })).labelsHidden() }
            if renameID == conversation.id {
                TextField("会話の名前", text: $renameText).focused($renameFocus, equals: conversation.id)
                    .onSubmit { renameID = nil; Task { await workspace.rename(id: conversation.id, title: renameText) } }
                    .onExitCommand { renameID = nil }
            } else {
                Button { Task { await workspace.select(conversation.id) } } label: {
                    HStack {
                        if conversation.isPinned { Image(systemName: "pin.fill").font(.caption) }
                        Text(conversation.title).lineLimit(1)
                        Spacer(minLength: 0)
                        if conversation.isRunning { ProgressView().controlSize(.mini) }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("会話：" + conversation.title)
            }
            Menu {
                Button(conversation.isPinned ? "ピンを外す" : "ピン留め") { Task { await workspace.pin(id: conversation.id, pinned: !conversation.isPinned) } }
                Button("名前を変更") { renameText = conversation.title; renameID = conversation.id; renameFocus = conversation.id }
                Button("削除", role: .destructive) { deletion = [conversation.id] }
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().disabled(workspace.busy)
                .accessibilityLabel("会話の操作：" + conversation.title)
        }.padding(.vertical, 5).padding(.horizontal, 4)
            .background(store.selectedID == conversation.id ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .accessibilityElement(children: .contain)
    }
}
