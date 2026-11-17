import AppKit
import NetworkPNTRCore
import SwiftUI

private struct MCPConsentOwner: Hashable {
    let runtime: UUID?
    let account: UUID?
}
private struct MCPConsentDraft: Identifiable {
    let id = UUID()
    let name: String
    let agents: Bool
    let tasks: [TaskRecord]
    let owner: MCPConsentOwner
}

@MainActor struct MCPConnectionsView: View {
    let environment: DesktopRuntime
    let helper: URL
    @Environment(\.locale) private var locale
    @State private var name = ""
    @State private var allowAgents = true
    @State private var tasks: [TaskRecord] = []
    @State private var selectedTasks: Set<String> = []
    @State private var loading = false
    @State private var loadTicket = UUID()
    @State private var taskError = false
    @State private var errorKey: AppStringKey?
    @State private var copied: UUID?
    @State private var draft: MCPConsentDraft?
    private var store: MCPClientStore { environment.mcp }
    private var language: AppLanguage { .preferred(in: [locale.identifier]) }
    private var owner: MCPConsentOwner { .init(runtime: environment.mcpRuntimeEpoch, account: environment.authentication?.exportSessionGeneration) }
    private var ready: Bool { owner.runtime != nil && owner.account != nil }
    private var hasHelper: Bool { FileManager.default.isExecutableFile(atPath: helper.path) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }

    init(environment: DesktopRuntime, helper: URL? = nil) {
        self.environment = environment
        self.helper = helper ?? (Bundle.main.executableURL?.deletingLastPathComponent() ?? Bundle.main.bundleURL).appendingPathComponent("NetworkPNTRMCP")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(s(.mcpClientsTitle)).font(.largeTitle.bold())
                Text(s(.mcpClientsDescription)).foregroundStyle(.secondary)
                Label(s(.mcpClientsReadOnly), systemImage: "lock.shield").foregroundStyle(.secondary)
                if !ready { Text(s(.mcpClientsLoginRequired)).foregroundStyle(.secondary) }
                if !hasHelper { Text(s(.mcpClientsHelperUnavailable)).foregroundStyle(.red) }
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField(s(.mcpClientsClientName), text: $name, prompt: Text(s(.mcpClientsPlaceholder)))
                            .accessibilityIdentifier("mcp-client-name")
                        Toggle(s(.mcpClientsAgentPermission), isOn: $allowAgents)
                        Text(s(.mcpClientsTaskPermission)).font(.headline)
                        if loading { ProgressView(s(.mcpClientsTasksLoading)) }
                        if taskError { Text(s(.mcpClientsTaskLoadError)).foregroundStyle(.red) }
                        if tasks.isEmpty, !loading { Text(s(.mcpClientsNoTasks)).foregroundStyle(.secondary) }
                        if !tasks.isEmpty {
                            ScrollView {
                                LazyVStack(alignment: .leading) {
                                    ForEach(tasks) { task in
                                        Toggle(isOn: Binding(get: { selectedTasks.contains(task.id) }, set: {
                                            if $0 { selectedTasks.insert(task.id) } else { selectedTasks.remove(task.id) }
                                        })) {
                                            Text(task.name) + Text(" · " + task.id).foregroundColor(.secondary)
                                        }.accessibilityIdentifier("mcp-allow-task-" + task.id)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.frame(maxHeight: 160)
                        }
                        HStack {
                            Button(s(.mcpClientsReload)) { Task { await loadTasks() } }.disabled(loading)
                            Spacer()
                            Button(s(.mcpClientsAllow)) { prepareConsent() }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("mcp-allow-connection")
                                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (!allowAgents && selectedTasks.isEmpty))
                        }
                    }.padding(6)
                }.disabled(!ready || !hasHelper || store.isBusy)
                if let errorKey { Text(s(errorKey)).foregroundStyle(.red).accessibilityIdentifier("mcp-connection-error") }
                Text(s(.mcpClientsActiveTitle)).font(.title2.bold())
                if store.connections.isEmpty { Text(s(.mcpClientsNoClients)).foregroundStyle(.secondary) }
                ForEach(store.connections) { connection in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(connection.name).font(.headline)
                            if connection.agents { Label(s(.mcpClientsAgentPermission), systemImage: "checkmark") }
                            if !connection.taskIDs.isEmpty {
                                Text(s(.mcpClientsSelectedTasks) + ": " + connection.taskIDs.sorted().joined(separator: ", "))
                                    .font(.callout).textSelection(.enabled)
                            }
                            HStack {
                                Button(s(.mcpClientsCopy)) { copy(connection) }
                                    .disabled(!ready || !hasHelper || store.isBusy)
                                Button(s(.mcpClientsRevoke), role: .destructive) {
                                    Task { await store.revoke(id: connection.id) }
                                }.disabled(store.retiring.contains(connection.id))
                                if store.retiring.contains(connection.id) { ProgressView().controlSize(.small) }
                                if copied == connection.id { Text(s(.mcpClientsCopied)).foregroundStyle(.secondary) }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    }.accessibilityIdentifier("mcp-client-" + connection.id.uuidString)
                }
                Text(s(.mcpClientsInstructions)).font(.callout).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: 900, alignment: .leading)
        }
        .navigationTitle(s(.mcpClientsTitle))
        .task(id: owner) { draft = nil; selectedTasks = []; name = ""; copied = nil; errorKey = nil; await loadTasks() }
        .sheet(item: $draft) { candidate in
            VStack(alignment: .leading, spacing: 16) {
                Text(s(.mcpClientsConsentTitle)).font(.title2.bold())
                Text(candidate.name).font(.headline)
                Text(s(.mcpClientsConsentBody))
                if candidate.agents { Label(s(.mcpClientsAgentPermission), systemImage: "checkmark") }
                if !candidate.tasks.isEmpty {
                    Text(s(.mcpClientsTaskPermission)).font(.headline)
                    ScrollView {
                        VStack(alignment: .leading) {
                            ForEach(candidate.tasks) { task in Text(task.name + " · " + task.id) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 180)
                }
                Text(s(.mcpClientsReadOnly)).foregroundStyle(.secondary)
                HStack {
                    Button(s(.mcpClientsCancel)) { if draft?.id == candidate.id { draft = nil } }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(s(.mcpClientsAllow)) { authorize(candidate) }.keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("mcp-confirm-allow")
                }
            }.padding(24).frame(width: 520)
        }
    }

    private func prepareConsent() {
        errorKey = nil
        guard ready, hasHelper, !store.isBusy else { errorKey = .mcpClientsConnectionError; return }
        let selected = tasks.filter { selectedTasks.contains($0.id) }
        guard selected.count == selectedTasks.count else { errorKey = .mcpClientsTaskError; return }
        draft = .init(name: name, agents: allowAgents, tasks: selected, owner: owner)
    }

    private func authorize(_ candidate: MCPConsentDraft) {
        guard draft?.id == candidate.id else { return }
        draft = nil
        guard owner == candidate.owner, ready, hasHelper else { errorKey = .mcpClientsConnectionError; return }
        do {
            try environment.authorizeMCPClient(name: candidate.name, agents: candidate.agents,
                                               taskIDs: Set(candidate.tasks.map(\.id)), language: language)
            name = ""; selectedTasks = []; errorKey = nil
        } catch let error as MCPClientInputError {
            switch error {
            case .name: errorKey = .mcpClientsNameError
            case .tasks: errorKey = .mcpClientsTaskError
            case .permissions: errorKey = .mcpClientsPermissionError
            case .retiring: errorKey = .mcpClientsBusyError
            case .capacity: errorKey = .mcpClientsCapacityError
            }
        } catch { errorKey = .mcpClientsConnectionError }
    }

    private func copy(_ connection: MCPClientConnection) {
        do {
            let configuration = try connection.clientConfiguration(helper: helper)
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.setString(configuration, forType: .string) else { throw MCPIPCError.unavailable }
            copied = connection.id
        } catch { errorKey = .mcpClientsConnectionError }
    }

    private func loadTasks() async {
        let captured = owner
        let ticket = UUID()
        loadTicket = ticket
        tasks = []; selectedTasks = []; taskError = false
        guard ready, let session = environment.authentication else { loading = false; return }
        loading = true
        defer { if owner == captured, loadTicket == ticket { loading = false } }
        do {
            let result = try await TaskService(client: AuthenticatedBackendClient(session: session)).list()
            guard !Task.isCancelled, owner == captured, loadTicket == ticket else { return }
            tasks = result.tasks
        } catch is CancellationError {} catch { if owner == captured, loadTicket == ticket { taskError = true } }
    }
}
