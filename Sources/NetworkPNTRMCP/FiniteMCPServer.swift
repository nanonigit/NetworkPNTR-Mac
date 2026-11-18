import NetworkPNTRCore
import Foundation
import MCP

/// Uses official MCP message codecs with app-owned, bounded request lifetimes.
actor FiniteMCPServer {
    private struct Envelope: Decodable {
        let jsonrpc: String
        let id: ID?
        let method: String
    }
    private struct Pending {
        let ticket: UUID
        let task: Task<Void, Never>
    }
    private enum Phase { case fresh, awaitingInitialized, ready }
    private let client: MCPIPCClient
    private let transport: BoundedStdioTransport
    private var phase = Phase.fresh
    private var pending: [ID: Pending] = [:]
    private var failed = false

    init(client: MCPIPCClient, transport: BoundedStdioTransport) {
        self.client = client
        self.transport = transport
    }

    func run() async throws {
        try await transport.connect()
        do {
            let stream = await transport.receive()
            for try await data in stream {
                let envelope = try JSONDecoder().decode(Envelope.self, from: data)
                guard envelope.jsonrpc == "2.0", !failed else { throw MCPIPCError.invalidFrame }
                if let id = envelope.id {
                    guard let ticket = await transport.requestTicket(id: id), pending[id] == nil else { throw MCPIPCError.invalidFrame }
                    if envelope.method == CallTool.name, phase == .ready {
                        guard pending.count < 8 else { throw MCPIPCError.invalidFrame }
                        let task = Task { [self] in
                            await call(data, id: id)
                            await complete(id: id, ticket: ticket)
                        }
                        pending[id] = Pending(ticket: ticket, task: task)
                    } else {
                        do { try await immediate(data, envelope: envelope, id: id) }
                        catch { await transport.retire(id: id, ticket: ticket); throw error }
                        await transport.retire(id: id, ticket: ticket)
                    }
                } else {
                    switch envelope.method {
                    case InitializedNotification.name:
                        _ = try JSONDecoder().decode(Message<InitializedNotification>.self, from: data)
                        if phase == .awaitingInitialized { phase = .ready }
                    case CancelledNotification.name:
                        let id = try Self.cancellationTarget(data)
                        if let entry = pending[id] {
                            entry.task.cancel()
                            await entry.task.value
                        }
                    default: break
                    }
                }
            }
            await drain()
        } catch {
            await drain()
            throw error
        }
    }

    nonisolated static func cancellationTarget(_ data: Data) throws -> ID {
        struct Parameters: Decodable {
            let requestId: ID
            private enum CodingKeys: CodingKey { case requestId }
            init(from decoder: any Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                if let string = try? values.decode(String.self, forKey: .requestId) { requestId = .string(string) }
                else if let integer = try? values.decode(Int.self, forKey: .requestId) { requestId = .number(integer) }
                else { throw MCPIPCError.invalidFrame }
            }
        }
        struct Cancellation: Decodable { let params: Parameters }
        _ = try JSONDecoder().decode(Message<CancelledNotification>.self, from: data)
        return try JSONDecoder().decode(Cancellation.self, from: data).params.requestId
    }

    private func drain() async {
        let tasks = pending.values.map(\.task)
        for task in tasks { task.cancel() }
        for task in tasks { await task.value }
        pending.removeAll()
        await transport.disconnect()
    }

    private func complete(id: ID, ticket: UUID) async {
        guard pending[id]?.ticket == ticket else { return }
        pending.removeValue(forKey: id)
        await transport.retire(id: id, ticket: ticket)
    }

    private func immediate(_ data: Data, envelope: Envelope, id: ID) async throws {
        do {
            switch envelope.method {
            case Initialize.name:
                guard phase == .fresh else { throw MCPError.invalidRequest("Already initialized") }
                let request = try JSONDecoder().decode(Request<Initialize>.self, from: data)
                let requested = request.params.protocolVersion
                let version = Version.supported.contains(requested) ? requested : Version.latest
                let result = Initialize.Result(protocolVersion: version, capabilities: .init(tools: .init()),
                                               serverInfo: .init(name: "NetworkPNTR Mac", version: "0.1.0"))
                try await send(Response<Initialize>(id: id, result: result))
                phase = .awaitingInitialized
            case Ping.name:
                _ = try JSONDecoder().decode(Request<Ping>.self, from: data)
                try await send(Response<Ping>(id: id, result: .init()))
            default:
                guard phase == .ready else { throw MCPError.invalidRequest("Initialize the connection first") }
                guard envelope.method == ListTools.name else { throw MCPError.methodNotFound("Unknown method") }
                _ = try JSONDecoder().decode(Request<ListTools>.self, from: data)
                try await send(Response<ListTools>(id: id, result: .init(tools: Self.tools)))
            }
        } catch let error as MCPError {
            try await send(Response<Ping>(id: id, error: error))
        } catch is DecodingError {
            try await send(Response<Ping>(id: id, error: .invalidParams("Invalid request parameters")))
        }
    }

    private func call(_ data: Data, id: ID) async {
        do {
            try Task.checkCancellation()
            let parameters = try JSONDecoder().decode(Request<CallTool>.self, from: data).params
            let arguments = parameters.arguments ?? [:]
            let operation: MCPIPCOperation
            let taskID: String?
            switch parameters.name {
            case "networkpntr_agents_list":
                guard arguments.isEmpty else { throw MCPError.invalidParams("This tool accepts no arguments") }
                operation = .agents
                taskID = nil
            case "networkpntr_task_status":
                guard Set(arguments.keys) == ["id"], case .string(let value) = arguments["id"],
                      value.utf8.count <= 19, value.first.map({ $0 >= "1" && $0 <= "9" }) == true,
                      value.utf8.allSatisfy({ (48...57).contains($0) }), Int64(value) != nil else {
                    throw MCPError.invalidParams("A canonical positive decimal task ID is required")
                }
                operation = .taskStatus
                taskID = value
            default: throw MCPError.invalidParams("Unknown tool")
            }
            let result: CallTool.Result
            do {
                let payload = try await client.call(operation, taskID: taskID)
                guard let text = String(data: payload, encoding: .utf8) else { throw MCPIPCError.invalidFrame }
                result = .init(content: [.text(text: text, annotations: nil, _meta: nil)])
            } catch is CancellationError { throw CancellationError() }
            catch {
                result = .init(content: [.text(text: "NetworkPNTR operation unavailable or not authorized. Check the app connection and client permissions.", annotations: nil, _meta: nil)], isError: true)
            }
            try Task.checkCancellation()
            try await send(Response<CallTool>(id: id, result: result))
        } catch is CancellationError {
            // Cancellation suppresses its response; completion still retires this exact ticket.
        } catch {
            do {
                try Task.checkCancellation()
                let error = error as? MCPError ?? MCPError.invalidParams("Invalid request parameters")
                try await send(Response<CallTool>(id: id, error: error))
            } catch is CancellationError {} catch { failed = true }
        }
    }

    private func send<M: MCP.Method>(_ response: Response<M>) async throws {
        try await transport.send(JSONEncoder().encode(response))
    }

    private static let tools: [Tool] = [
        Tool(name: "networkpntr_agents_list", description: "Read agent names and availability. Does not run a NetworkPNTR agent or call a model.",
             inputSchema: .object(["type": .string("object"), "properties": .object([:]), "additionalProperties": .bool(false)]),
             annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)),
        Tool(name: "networkpntr_task_status", description: "Read status and existing token counts for a task explicitly authorized in NetworkPNTR Mac. Does not start or resume a task.",
             inputSchema: .object(["type": .string("object"), "properties": .object(["id": .object(["type": .string("string"), "pattern": .string("^[1-9][0-9]*$")])]), "required": .array([.string("id")]), "additionalProperties": .bool(false)]),
             annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false))
    ]
}
