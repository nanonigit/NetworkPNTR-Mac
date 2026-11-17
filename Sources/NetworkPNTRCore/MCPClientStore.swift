import Foundation
import Observation

public enum MCPClientInputError: Error { case name, tasks, permissions, retiring, capacity }

public struct MCPClientConnection: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let agents: Bool
    public let taskIDs: Set<String>
    public let connectionFile: URL

    public func clientConfiguration(helper: URL) throws -> String {
        let server: [String: Any] = ["command": helper.path, "args": ["--connection-file", connectionFile.path]]
        let value: [String: Any] = ["mcpServers": ["networkpntr-mac": server]]
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else { throw MCPIPCError.invalidConnection }
        return text
    }
}

/// App-owned temporary authorizations. No provider configuration or model invocation is involved.
@MainActor @Observable public final class MCPClientStore {
    public private(set) var connections: [MCPClientConnection] = []
    public private(set) var retiring: Set<UUID> = []
    public private(set) var invalidatingAll = false
    public var isBusy: Bool { invalidatingAll || !retiring.isEmpty }
    private struct Entry {
        let server: MCPIPCServer
        let valid: @MainActor () -> Bool
    }
    @ObservationIgnored private var entries: [UUID: Entry] = [:]
    @ObservationIgnored private var retirements: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var monitor: Task<Void, Never>?
    @ObservationIgnored private var acquiring = false

    public init() {}

    public func authorize(name: String, agents: Bool, taskIDs: Set<String>, language: AppLanguage,
                          session: AuthenticationSession, runtimeEpoch: @escaping @MainActor () -> UUID?) throws -> MCPClientConnection {
        guard !isBusy, !acquiring else { throw MCPClientInputError.retiring }
        acquiring = true
        defer { acquiring = false }
        guard connections.count < 16 else { throw MCPClientInputError.capacity }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80, name.utf8.count <= 320,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.union(.newlines).contains($0) }) else { throw MCPClientInputError.name }
        guard taskIDs.count <= 1_000 else { throw MCPClientInputError.tasks }
        do { for id in taskIDs { try TaskWire.validateID(id) } } catch { throw MCPClientInputError.tasks }
        var scopes = Set<MCPReadScope>()
        if agents { scopes.insert(.agents) }
        if !taskIDs.isEmpty { scopes.insert(.taskStatus) }
        guard !scopes.isEmpty else { throw MCPClientInputError.permissions }
        guard let runtime = runtimeEpoch(), let account = session.exportSessionGeneration else { throw MCPReadError.unauthorized }
        let broker = try MCPReadBroker(session: session, runtimeEpoch: runtimeEpoch)
        let grant = try broker.authorize(scopes: scopes, taskIDs: taskIDs)
        let currentRuntime = runtimeEpoch()
        guard !isBusy, connections.count < 16, currentRuntime == runtime, session.exportSessionGeneration == account else {
            broker.revoke(grant)
            throw MCPReadError.unauthorized
        }
        let id = UUID()
        let directory = URL(fileURLWithPath: "/private/tmp/networkpntr-mcp-" + id.uuidString, isDirectory: true)
        let server: MCPIPCServer
        do { server = try MCPIPCServer(directory: directory, broker: broker, grant: grant, language: language) }
        catch { broker.revoke(grant); throw error }
        let connection = MCPClientConnection(id: id, name: name, agents: agents, taskIDs: taskIDs, connectionFile: server.connectionFile)
        entries[id] = Entry(server: server, valid: { [weak session] in
            let currentRuntime = runtimeEpoch()
            return currentRuntime == runtime && session?.exportSessionGeneration == account
        })
        connections.append(connection)
        startMonitor()
        return connection
    }

    public func invalidateAll() {
        invalidatingAll = true
        for entry in entries.values { entry.server.invalidate() }
    }

    public func revoke(id: UUID) async {
        guard let entry = entries[id] else { return }
        let task: Task<Void, Never>
        if let existing = retirements[id] { task = existing }
        else {
            entry.server.invalidate()
            retiring.insert(id)
            task = Task { await entry.server.stop() }
            retirements[id] = task
        }
        await task.value
        entries.removeValue(forKey: id)
        connections.removeAll { $0.id == id }
        retirements.removeValue(forKey: id)
        retiring.remove(id)
    }

    public func revokeAll() async {
        invalidateAll()
        let ids = Array(entries.keys)
        for id in ids { await revoke(id: id) }
        invalidatingAll = false
    }

    public func reconcile() async {
        let stale = entries.compactMap { $0.value.valid() ? nil : $0.key }
        for id in stale { await revoke(id: id) }
    }

    private func startMonitor() {
        guard monitor == nil else { return }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard let self else { return }
                await self.reconcile()
                if self.entries.isEmpty { self.monitor = nil; return }
            }
        }
    }

    deinit { monitor?.cancel() }
}
