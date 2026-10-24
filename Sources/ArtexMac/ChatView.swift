import ArtexCore
import SwiftUI

struct ChatView: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }

    @State private var workspace: ChatWorkspace
    @State private var pickingFiles = false
    @State private var pickerError: AppStringKey?
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
                    Button { Task { await workspace.select(nil) } } label: { Label(s(.chatNew), systemImage: "plus").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                    Picker(s(.chatFilter), selection: $filter) {
                        Text(s(.chatAllAgents)).tag("")
                        ForEach(Array(Set(store.conversations.map(\.agentKey) + workspace.agents.map(\.key))).sorted(), id: \.self) { key in Text(agentName(key)).tag(key) }
                    }.labelsHidden().accessibilityLabel(s(.chatFilter))
                    HStack {
                        Toggle(s(.chatMultiSelect), isOn: $batchMode).toggleStyle(.button)
                        Spacer()
                        if batchMode { Button(s(.chatDelete) + " (\(checked.count))", role: .destructive) { deletion = Array(checked) }.disabled(checked.isEmpty || workspace.busy) }
                    }.font(.caption)
                }.padding(12)
                Divider()
                if let error = store.listError { Text(error).font(.caption).foregroundStyle(.red).padding(8) }
                List {
                    if !visible.filter(\.isPinned).isEmpty {
                        Section(s(.chatPinned)) { ForEach(visible.filter(\.isPinned)) { conversationRow($0) } }
                    }
                    ForEach(keys, id: \.self) { key in
                        DisclosureGroup(isExpanded: Binding(get: { !collapsed.contains(key) }, set: { expanded in
                            var values = collapsed; if expanded { values.remove(key) } else { values.insert(key) }
                            if let data = try? JSONEncoder().encode(values.sorted()), let value = String(data: data, encoding: .utf8) { collapsedJSON = value }
                        })) {
                            ForEach(visible.filter { !$0.isPinned && $0.agentKey == key }) { conversationRow($0) }
                        } label: { Text(agentName(key)).font(.caption.bold()) }
                    }
                    if filtered.count > visibleCount { Button(s(.chatShow100)) { visibleCount += 100 } }
                    if store.conversations.isEmpty { Text(store.isLoadingList ? s(.chatLoading) : s(.chatNoConversations)).foregroundStyle(.secondary) }
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
        .navigationTitle(AppStrings.text(.chat, language: language))
        .task { await workspace.load(); await store.pollList() }
        .task(id: store.selectedID) { await store.pollSelected() }
        .onDisappear {
            for task in uploadTasks.values { task.cancel() }
            uploadTasks.removeAll(); pickingFiles = false; workspace.stop()
        }
        .onChange(of: store.selectedID) { _, _ in pickingFiles = false; pickerError = nil }
        .onChange(of: filter) { _, _ in visibleCount = 100 }
        .onChange(of: batchMode) { _, active in if !active { checked = [] } }
        .confirmationDialog(s(.chatDeleteQuestion), isPresented: Binding(get: { !deletion.isEmpty }, set: { if !$0 { deletion = [] } }), titleVisibility: .visible) {
            Button(s(.chatDeleteConversation), role: .destructive) {
                let ids = deletion; deletion = []
                Task { let result = await workspace.delete(ids: ids); checked.subtract(result.filter(\.ok).map(\.id)) }
            }
            Button(s(.chatCancel), role: .cancel) { deletion = [] }
        } message: { Text(s(.chatDeleteMessage)) }
    }
    private func agentName(_ key: String) -> String { BuiltinAgentText.name(key: key, original: workspace.name(for: key), language: language) }
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(workspace.selected?.title ?? s(.chatNew)).font(.headline).lineLimit(1)
                if let selected = workspace.selected { Text(agentName(selected.agentKey)).font(.caption).foregroundStyle(.secondary) }
                else {
                    Picker(s(.chatAgent), selection: Binding(get: { workspace.agentKey }, set: { workspace.agentKey = $0 })) {
                        Text(s(.chatChoose)).tag("")
                        ForEach(workspace.agents) { Text(BuiltinAgentText.name(key: $0.key, original: $0.name, language: language)).tag($0.key) }
                    }.frame(maxWidth: 240)
                }
            }
            Spacer()
            Picker(s(.chatModel), selection: Binding<Int64?>(get: { store.selectedID == nil ? workspace.draftProfileID : workspace.selected?.llmProfileId }, set: { id in
                if let selected = store.selectedID { Task { await workspace.changeProfile(id: selected, profileID: id) } }
                else { workspace.draftProfileID = id }
            })) {
                Text(s(.chatDefaultModel)).tag(nil as Int64?)
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
            if let error = pickerError.map { s($0) } ?? workspace.uploadError ?? workspace.error ?? store.mutationError {
                Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            if !store.attachments.isEmpty {
                attachmentStrip(owner: store.selectedID ?? 0)
            }
            if let upload = workspace.uploadState(for: store.selectedID) {
                uploadProgress(upload, owner: store.selectedID)
            }
            if let agent = workspace.agents.first(where: { $0.key == workspace.agentKey }), store.selectedID == nil {
                Text(BuiltinAgentText.description(key: agent.key, original: agent.description, language: language)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            ChatMentionComposer(text: ChatComposer.draftBinding(store: store, conversationID: store.selectedID), service: workspace.mentionService, mode: sendMode, disabled: composerAvailability.editorDisabled, send: send)
                .id(store.selectedID ?? 0)
            HStack {
                attachmentPicker(owner: store.selectedID)
                Picker(s(.chatSendKey), selection: $sendMode) { Text(s(.chatEnter)).tag("enter"); Text(s(.chatCtrlEnter)).tag("ctrl-enter") }
                    .labelsHidden().frame(maxWidth: 220).accessibilityLabel(s(.chatSendKey))
                Spacer()
                if store.running {
                    Button(store.isStopping ? s(.chatStopping) : s(.chatStop), role: .destructive) { Task { _ = await store.requestStop() } }.disabled(store.isStopping)
                } else {
                    Button { send() } label: { Label(store.isSending || workspace.busy ? s(.chatSending) : s(.chatSend), systemImage: "arrow.up") }
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
        ChatAttachmentProgressView(presentation: ChatUploadPresentation(progress: upload.progress, language: language)) {
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
                    if owner == store.selectedID { pickerError = .chatFileReadFailure }
                }
            }
        }, onPresentation: { presented in
            if owner == store.selectedID { pickingFiles = presented; if presented { pickerError = nil } }
        }, onError: {
            if owner == store.selectedID { pickerError = .chatPickerFailure }
        })
        .id(owner ?? 0).frame(width: 128, height: 28)
    }
    private func conversationRow(_ conversation: ChatConversation) -> some View {
        HStack(spacing: 5) {
            if batchMode { Toggle(s(.chatSelectPrefix) + conversation.title, isOn: Binding(get: { checked.contains(conversation.id) }, set: { value in if value { checked.insert(conversation.id) } else { checked.remove(conversation.id) } })).labelsHidden() }
            if renameID == conversation.id {
                TextField(s(.chatConversationName), text: $renameText).focused($renameFocus, equals: conversation.id)
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
                }.buttonStyle(.plain).accessibilityLabel(s(.chatConversationPrefix) + conversation.title)
            }
            Menu {
                Button(conversation.isPinned ? s(.chatUnpin) : s(.chatPinned)) { Task { await workspace.pin(id: conversation.id, pinned: !conversation.isPinned) } }
                Button(s(.chatRename)) { renameText = conversation.title; renameID = conversation.id; renameFocus = conversation.id }
                Button(s(.chatDelete), role: .destructive) { deletion = [conversation.id] }
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().disabled(workspace.busy)
                .accessibilityLabel(s(.chatActionsPrefix) + conversation.title)
        }.padding(.vertical, 5).padding(.horizontal, 4)
            .background(store.selectedID == conversation.id ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .accessibilityElement(children: .contain)
    }
}
