import Darwin
import Foundation
import Security

public enum MCPIPCError: Error { case unavailable, invalidConnection, invalidFrame, unauthorized }
public enum MCPIPCOperation: String, Codable, Sendable { case agents, taskStatus }

public struct MCPIPCConnection: Codable, Sendable {
    let version: Int
    let socketPath: String
    let capability: String

    public static func load(from file: URL) throws -> Self {
        let directory = file.deletingLastPathComponent()
        var info = stat()
        guard lstat(directory.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == geteuid(), info.st_mode & 0o777 == 0o700 else { throw MCPIPCError.invalidConnection }
        let fd = open(file.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw MCPIPCError.invalidConnection }
        defer { close(fd) }
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == geteuid(), info.st_mode & 0o777 == 0o600,
              info.st_size > 0, info.st_size <= 4_096 else { throw MCPIPCError.invalidConnection }
        var bytes = [UInt8](repeating: 0, count: Int(info.st_size))
        let count = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
        guard count == bytes.count else { throw MCPIPCError.invalidConnection }
        let result = try JSONDecoder().decode(Self.self, from: Data(bytes))
        guard result.version == 1, result.capability.count == 64,
              result.capability.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              URL(fileURLWithPath: result.socketPath).deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
              URL(fileURLWithPath: result.socketPath).lastPathComponent == "broker.sock" else { throw MCPIPCError.invalidConnection }
        return result
    }
}

private struct MCPIPCRequest: Codable, Sendable {
    let version: Int
    let requestID: UUID
    let capability: String
    let operation: MCPIPCOperation
    let taskID: String?
}
private struct MCPIPCReply: Codable {
    let version: Int
    let requestID: UUID
    let payload: Data?
    let denied: Bool
}

public struct MCPIPCClient: Sendable {
    private let connection: MCPIPCConnection
    public init(connection: MCPIPCConnection) { self.connection = connection }

    public func call(_ operation: MCPIPCOperation, taskID: String? = nil) async throws -> Data {
        let connection = connection
        let worker = Task.detached {
            let deadline = ContinuousClock.now + .seconds(10)
            let fd = try await MCPIPCSocket.connect(path: connection.socketPath, deadline: deadline)
            defer { close(fd) }
            try MCPIPCSocket.requirePeer(fd)
            let request = MCPIPCRequest(version: 1, requestID: UUID(), capability: connection.capability,
                                        operation: operation, taskID: taskID)
            try await MCPIPCSocket.writeFrame(JSONEncoder().encode(request), fd: fd, deadline: deadline, maximum: 16_384)
            let reply = try await JSONDecoder().decode(MCPIPCReply.self, from: MCPIPCSocket.readFrame(fd, deadline: deadline, maximum: 1_048_576))
            guard reply.version == 1, reply.requestID == request.requestID else { throw MCPIPCError.invalidFrame }
            guard !reply.denied, let payload = reply.payload else { throw MCPIPCError.unauthorized }
            return payload
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: { worker.cancel() }
    }
}

@MainActor public final class MCPIPCServer {
    public let connectionFile: URL
    private let directory: URL
    private let broker: MCPReadBroker
    private let grant: MCPReadBroker.Grant
    private let directoryDevice: dev_t
    private let directoryInode: ino_t
    private var worker: Task<Void, Never>?

    /// Creates a new, private directory. The app must obtain client consent before calling this.
    public init(directory: URL, broker: MCPReadBroker, grant: MCPReadBroker.Grant, language: AppLanguage) throws {
        self.directory = directory
        self.broker = broker
        self.grant = grant
        connectionFile = directory.appendingPathComponent("connection.json")
        guard mkdir(directory.path, 0o700) == 0 else { throw MCPIPCError.invalidConnection }
        var directoryInfo = stat()
        guard lstat(directory.path, &directoryInfo) == 0 else { throw MCPIPCError.invalidConnection }
        directoryDevice = directoryInfo.st_dev
        directoryInode = directoryInfo.st_ino
        var installed = false
        defer { if !installed { try? FileManager.default.removeItem(at: directory) } }
        var random = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else { throw MCPIPCError.invalidConnection }
        let capability = random.map { String(format: "%02x", $0) }.joined()
        let socketPath = directory.appendingPathComponent("broker.sock").path
        let fd = try MCPIPCSocket.make()
        var transferred = false
        defer { if !transferred { close(fd) } }
        var address = try MCPIPCSocket.address(socketPath)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0, chmod(socketPath, 0o600) == 0, listen(fd, 8) == 0 else { throw MCPIPCError.unavailable }
        let configuration = MCPIPCConnection(version: 1, socketPath: socketPath, capability: capability)
        let file = open(connectionFile.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard file >= 0 else { throw MCPIPCError.invalidConnection }
        do {
            let bytes = try JSONEncoder().encode(configuration)
            let count = bytes.withUnsafeBytes { Darwin.write(file, $0.baseAddress, $0.count) }
            guard count == bytes.count else { throw MCPIPCError.invalidConnection }
            close(file)
        } catch { close(file); throw error }
        let device = directoryDevice, inode = directoryInode
        worker = Task.detached {
            defer {
                close(fd)
                var info = stat()
                if lstat(directory.path, &info) == 0, info.st_dev == device, info.st_ino == inode {
                    try? FileManager.default.removeItem(at: directory)
                }
            }
            while !Task.isCancelled {
                let client = accept(fd, nil, nil)
                if client < 0 {
                    if errno == EAGAIN || errno == EINTR || errno == ECONNABORTED {
                        try? await Task.sleep(for: .milliseconds(20))
                        continue
                    }
                    break
                }
                do {
                    defer { close(client) }
                    try MCPIPCSocket.configure(client)
                    try MCPIPCSocket.requirePeer(client)
                    let deadline = ContinuousClock.now + .seconds(10)
                    let request = try await JSONDecoder().decode(MCPIPCRequest.self, from: MCPIPCSocket.readFrame(client, deadline: deadline, maximum: 16_384))
                    guard request.version == 1, request.capability == capability else { throw MCPIPCError.unauthorized }
                    var payload: Data?
                    do { payload = try await Self.readPayload(request, broker: broker, grant: grant, language: language, client: client, deadline: deadline) }
                    catch { payload = nil }
                    try Task.checkCancellation()
                    let reply = MCPIPCReply(version: 1, requestID: request.requestID, payload: payload, denied: payload == nil)
                    try await MCPIPCSocket.writeFrame(JSONEncoder().encode(reply), fd: client, deadline: deadline, maximum: 1_048_576)
                } catch {
                    // Protocol and authorization failures close this connection without diagnostic content.
                }
            }
        }
        transferred = true
        installed = true
    }

    nonisolated private static func readPayload(
        _ request: MCPIPCRequest, broker: MCPReadBroker, grant: MCPReadBroker.Grant,
        language: AppLanguage, client: Int32, deadline: ContinuousClock.Instant
    ) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                switch request.operation {
                case .agents:
                    guard request.taskID == nil else { throw MCPIPCError.invalidFrame }
                    return try await JSONEncoder().encode(broker.agents(grant: grant, language: language))
                case .taskStatus:
                    guard let id = request.taskID else { throw MCPIPCError.invalidFrame }
                    return try await JSONEncoder().encode(broker.taskStatus(grant: grant, id: id))
                }
            }
            group.addTask {
                while true {
                    try Task.checkCancellation()
                    guard ContinuousClock.now < deadline else { throw MCPIPCError.unavailable }
                    var descriptor = pollfd(fd: client, events: Int16(POLLIN), revents: 0)
                    let ready = poll(&descriptor, 1, 0)
                    if ready > 0 {
                        // One request per connection: EOF and additional bytes both retire it.
                        throw MCPIPCError.unavailable
                    }
                    if ready < 0, errno != EINTR { throw MCPIPCError.unavailable }
                    try await Task.sleep(for: .milliseconds(20))
                }
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw MCPIPCError.unavailable }
            return result
        }
    }

    public func stop() async {
        broker.revoke(grant)
        let task = worker
        task?.cancel()
        await task?.value
        if worker != nil {
            worker = nil
            var info = stat()
            if lstat(directory.path, &info) == 0, info.st_dev == directoryDevice, info.st_ino == directoryInode {
                try? FileManager.default.removeItem(at: directory)
            }
        }
    }

    deinit {
        worker?.cancel()
        let broker = broker, grant = grant
        Task { @MainActor in broker.revoke(grant) }
    }
}

private enum MCPIPCSocket {
    private struct ConnectFailure: Error { let code: Int32 }

    /// Retry only before any request bytes exist; never replay a dispatched operation.
    static func connect(path: String, deadline: ContinuousClock.Instant) async throws -> Int32 {
        while true {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw MCPIPCError.unavailable }
            let fd = try make()
            do {
                var endpoint = try address(path)
                let result = withUnsafePointer(to: &endpoint) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
                }
                if result != 0, errno != EINPROGRESS { throw ConnectFailure(code: errno) }
                try await ready(fd, events: Int16(POLLOUT), deadline: deadline)
                var code: Int32 = 0, size = socklen_t(MemoryLayout<Int32>.size)
                guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &code, &size) == 0 else { throw MCPIPCError.unavailable }
                guard code == 0 else { throw ConnectFailure(code: code) }
                return fd
            } catch let error as ConnectFailure {
                close(fd)
                var info = stat()
                guard [EAGAIN, ECONNREFUSED, EINTR].contains(error.code),
                      lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFSOCK,
                      info.st_uid == geteuid() else { throw MCPIPCError.unavailable }
                try await Task.sleep(for: .milliseconds(5))
            } catch { close(fd); throw error }
        }
    }

    static func make() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw MCPIPCError.unavailable }
        do { try configure(fd); return fd } catch { close(fd); throw error }
    }
    static func configure(_ fd: Int32) throws {
        var enabled: Int32 = 1
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0,
              fcntl(fd, F_SETFD, FD_CLOEXEC) == 0,
              setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw MCPIPCError.unavailable
        }
    }
    static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        let bytes = Array(path.utf8) + [0]
        guard path.hasPrefix("/"), !path.utf8.contains(0), bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw MCPIPCError.invalidConnection }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return address
    }
    static func requirePeer(_ fd: Int32) throws {
        var user: uid_t = 0, group: gid_t = 0
        guard getpeereid(fd, &user, &group) == 0, user == geteuid() else { throw MCPIPCError.unauthorized }
    }
    static func ready(_ fd: Int32, events: Int16, deadline: ContinuousClock.Instant) async throws {
        while true {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw MCPIPCError.unavailable }
            var descriptor = pollfd(fd: fd, events: events, revents: 0)
            let result = poll(&descriptor, 1, 0)
            if result > 0 {
                guard descriptor.revents & events != 0 else { throw MCPIPCError.unavailable }
                return
            }
            if result < 0, errno != EINTR { throw MCPIPCError.unavailable }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    static func readExact(_ count: Int, fd: Int32, deadline: ContinuousClock.Instant) async throws -> Data {
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: min(4_096, count))
        while result.count < count {
            try await ready(fd, events: Int16(POLLIN), deadline: deadline)
            let size = min(buffer.count, count - result.count)
            let amount = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, size) }
            if amount < 0, errno == EAGAIN || errno == EINTR { continue }
            guard amount > 0 else { throw MCPIPCError.invalidFrame }
            result.append(contentsOf: buffer.prefix(amount))
        }
        return result
    }
    static func readFrame(_ fd: Int32, deadline: ContinuousClock.Instant, maximum: Int) async throws -> Data {
        let header = try await readExact(4, fd: fd, deadline: deadline)
        let length = header.reduce(0) { ($0 << 8) | Int($1) }
        guard length > 0, length <= maximum else { throw MCPIPCError.invalidFrame }
        return try await readExact(length, fd: fd, deadline: deadline)
    }
    static func writeFrame(_ data: Data, fd: Int32, deadline: ContinuousClock.Instant, maximum: Int) async throws {
        guard !data.isEmpty, data.count <= maximum else { throw MCPIPCError.invalidFrame }
        let size = UInt32(data.count)
        var framed = Data([UInt8(size >> 24), UInt8(truncatingIfNeeded: size >> 16), UInt8(truncatingIfNeeded: size >> 8), UInt8(truncatingIfNeeded: size)])
        framed.append(data)
        var offset = 0
        while offset < framed.count {
            try await ready(fd, events: Int16(POLLOUT), deadline: deadline)
            let amount = framed.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!.advanced(by: offset), framed.count - offset) }
            if amount < 0, errno == EAGAIN || errno == EINTR { continue }
            guard amount > 0 else { throw MCPIPCError.unavailable }
            offset += amount
        }
    }
}
