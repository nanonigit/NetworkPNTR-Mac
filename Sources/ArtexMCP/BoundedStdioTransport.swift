import ArtexCore
import Darwin
import Foundation
import Logging
import MCP
import Synchronization

/// MCP newline framing with bounded input, queued messages and stalled-output lifetime.
actor BoundedStdioTransport: Transport {
    nonisolated let logger = Logger(label: "artex.mcp.stdio", factory: { _ in SwiftLogNoOpLogHandler() })
    private let input: Int32
    private let output: Int32
    private var outputFD: Int32?
    private var reader: Task<Void, Never>?
    private var connected = false
    private let writeTimeout: Duration
    private final class PendingRequests: Sendable { let ids = Mutex<[ID: UUID]>([:]) }
    private let pendingRequests = PendingRequests()
    private let stream: AsyncThrowingStream<Data, any Error>
    private let continuation: AsyncThrowingStream<Data, any Error>.Continuation

    init(input: Int32 = STDIN_FILENO, output: Int32 = STDOUT_FILENO, writeTimeout: Duration = .seconds(10)) {
        self.input = input
        self.output = output
        self.writeTimeout = writeTimeout
        (stream, continuation) = AsyncThrowingStream.makeStream(bufferingPolicy: .bufferingOldest(32))
    }

    func connect() throws {
        guard !connected else { return }
        let readFD = dup(input), writeFD = dup(output)
        guard readFD >= 0, writeFD >= 0 else {
            if readFD >= 0 { close(readFD) }
            if writeFD >= 0 { close(writeFD) }
            throw MCPIPCError.unavailable
        }
        do {
            try Self.configure(readFD)
            try Self.configure(writeFD)
        } catch { close(readFD); close(writeFD); throw error }
        connected = true
        outputFD = writeFD
        let continuation = continuation
        let pendingRequests = pendingRequests
        let rejectOverload: @Sendable (ID) async throws -> Void = { [weak self] id in
            guard let self else { throw MCPIPCError.unavailable }
            try await self.rejectOverload(id: id)
        }
        reader = Task.detached {
            defer { close(readFD) }
            do {
                var pending = Data()
                var bytes = [UInt8](repeating: 0, count: 4_096)
                while !Task.isCancelled {
                    var descriptor = pollfd(fd: readFD, events: Int16(POLLIN), revents: 0)
                    let ready = poll(&descriptor, 1, 0)
                    if ready == 0 { try await Task.sleep(for: .milliseconds(5)); continue }
                    if ready < 0 {
                        if errno == EINTR { continue }
                        throw MCPIPCError.unavailable
                    }
                    let amount = bytes.withUnsafeMutableBytes { Darwin.read(readFD, $0.baseAddress, $0.count) }
                    if amount == 0 {
                        guard pending.isEmpty else { throw MCPIPCError.invalidFrame }
                        break
                    }
                    if amount < 0 {
                        if errno == EAGAIN || errno == EINTR { continue }
                        throw MCPIPCError.unavailable
                    }
                    for byte in bytes.prefix(amount) {
                        if byte == 10 {
                            if !pending.isEmpty {
                                let header = try JSONDecoder().decode(Header.self, from: pending)
                                if header.method != nil, let id = header.id {
                                    let admission = pendingRequests.ids.withLock { ids -> Int in
                                        if ids[id] != nil { return -1 }
                                        guard ids.count < 8 else { return 0 }
                                        ids[id] = UUID()
                                        return 1
                                    }
                                    guard admission >= 0 else { throw MCPIPCError.invalidFrame }
                                    if admission == 0 {
                                        try await rejectOverload(id)
                                        pending.removeAll(keepingCapacity: true)
                                        continue
                                    }
                                }
                                switch continuation.yield(pending) {
                                case .enqueued: break
                                case .dropped, .terminated: throw MCPIPCError.invalidFrame
                                @unknown default: throw MCPIPCError.invalidFrame
                                }
                                pending.removeAll(keepingCapacity: true)
                            }
                        } else {
                            guard pending.count < 65_536 else { throw MCPIPCError.invalidFrame }
                            pending.append(byte)
                        }
                    }
                }
                continuation.finish()
            } catch { continuation.finish(throwing: MCPIPCError.invalidFrame) }
        }
    }

    func disconnect() async {
        connected = false
        let task = reader
        reader = nil
        task?.cancel()
        await task?.value
        if let fd = outputFD { close(fd); outputFD = nil }
        continuation.finish()
    }

    func send(_ data: Data) throws {
        guard connected, let fd = outputFD, data.count <= 2_097_152 else { throw MCPIPCError.unavailable }
        do { try write(data, fd: fd) }
        catch {
            connected = false
            outputFD = nil
            close(fd)
            reader?.cancel()
            continuation.finish(throwing: MCPIPCError.unavailable)
            throw error
        }
    }

    func requestTicket(id: ID) -> UUID? { pendingRequests.ids.withLock { $0[id] } }

    private func rejectOverload(id: ID) throws {
        let error = MCPError.internalError("ARTEX MCP request limit reached. Retry after pending requests finish.")
        try send(JSONEncoder().encode(Response<Ping>(id: id, error: error)))
    }

    /// Retire only this dispatch after its handler has drained, including suppressed responses.
    func retire(id: ID, ticket: UUID) {
        pendingRequests.ids.withLock { ids in
            if ids[id] == ticket { ids.removeValue(forKey: id) }
        }
    }

    private func write(_ data: Data, fd: Int32) throws {
        var framed = data
        framed.append(10)
        var offset = 0
        let deadline = ContinuousClock.now + writeTimeout
        while offset < framed.count {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw MCPIPCError.unavailable }
            var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let ready = poll(&descriptor, 1, 50)
            if ready == 0 { continue }
            if ready < 0, errno == EINTR { continue }
            guard ready > 0, descriptor.revents & Int16(POLLOUT) != 0 else { throw MCPIPCError.unavailable }
            let amount = framed.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!.advanced(by: offset), framed.count - offset) }
            if amount < 0, errno == EAGAIN || errno == EINTR { continue }
            guard amount > 0 else { throw MCPIPCError.unavailable }
            offset += amount
        }
    }

    func receive() -> AsyncThrowingStream<Data, any Error> { stream }

    private struct Header: Decodable {
        let id: ID?
        let method: String?
        private enum CodingKeys: CodingKey { case id, method }
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            method = try values.decodeIfPresent(String.self, forKey: .method)
            if !values.contains(.id) { id = nil }
            else if let string = try? values.decode(String.self, forKey: .id) { id = .string(string) }
            else if let integer = try? values.decode(Int.self, forKey: .id) { id = .number(integer) }
            else { throw MCPIPCError.invalidFrame }
        }
    }

    private static func configure(_ fd: Int32) throws {
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0,
              fcntl(fd, F_SETFD, FD_CLOEXEC) == 0 else { throw MCPIPCError.unavailable }
    }
}
