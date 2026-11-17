import Darwin
import Foundation

/// One guest request. Only the worker closes the owned descriptor. A stop or
/// peer disconnect shuts it down and cancels the upstream exchange.
final class CloudEgressSocketSession: Sendable {
    typealias Upstream = @Sendable (
        CloudEgressRequest, CloudEgressCancellation, ContinuousClock.Instant,
        @escaping (CloudEgressResponseEvent) throws -> Void
    ) throws -> Void

    private let socket: BackendUploadSocket
    private let cancellation = CloudEgressCancellation()
    private let upstream: Upstream
    private static let observerQueue = DispatchQueue(label: "artx.cloud-egress.peer", qos: .utility)

    init(owning descriptor: Int32, upstream: @escaping Upstream = CloudEgressTransport.exchangeFromBroker) {
        socket = BackendUploadSocket(owning: descriptor)
        self.upstream = upstream
    }

    func cancel() {
        cancellation.cancel()
        socket.cancel()
    }

    func run() {
        defer { socket.finish() }
        do {
            let fd = try socket.checkedDescriptor()
            let start = ContinuousClock.now
            let io = try CloudEgressSocketIO(fd: fd, cancellation: cancellation)
            let request = try readRequest(io, deadline: start + .seconds(10))
            let (watcher, drained) = try watchPeer(io)
            defer {
                watcher.cancel()
                drained.wait()
            }
            try io.checkPeer()
            let deadline = start + .seconds(120)
            let writer = CloudEgressSocketWriter(io: io, deadline: deadline)
            try upstream(request, cancellation, deadline, writer.receive)
        } catch {
            // Closing without a terminal frame is the wire failure signal.
        }
    }

    private func readRequest(_ io: CloudEgressSocketIO, deadline: ContinuousClock.Instant) throws -> CloudEgressRequest {
        let bytes = try io.readExactly(14, deadline: deadline)
        guard bytes.prefix(5).elementsEqual([65, 82, 88, 69, 1]),
              let route = Self.routes[bytes[5]], bytes[6] <= 1, bytes[7] == 0 else {
            throw CloudEgressError.invalidRequest
        }
        let keyLength = Int(bytes[8]) << 8 | Int(bytes[9])
        let bodyLength = bytes[10..<14].reduce(0) { ($0 << 8) | Int($1) }
        let streaming = bytes[6] == 1
        guard (1...CloudEgressRequest.maximumKeyBytes).contains(keyLength),
              bodyLength <= CloudEgressRequest.maximumBodyBytes,
              route.requiresBody == (bodyLength > 0), route.requiresBody || !streaming else {
            throw CloudEgressError.invalidRequest
        }
        let key = try io.readExactly(keyLength, deadline: deadline)
        guard key.allSatisfy({ (0x21...0x7e).contains($0) }) else { throw CloudEgressError.invalidRequest }
        let body = try io.readExactly(bodyLength, deadline: deadline)
        return try CloudEgressRequest(route: route, apiKey: String(decoding: key, as: UTF8.self), body: body, streaming: streaming)
    }

    private func watchPeer(_ io: CloudEgressSocketIO) throws -> (DispatchSourceRead, DispatchSemaphore) {
        let observer = fcntl(io.fd, F_DUPFD_CLOEXEC, 0)
        guard observer >= 0 else { throw POSIXError(.EIO) }
        let drained = DispatchSemaphore(value: 0)
        let watcher = DispatchSource.makeReadSource(fileDescriptor: observer, queue: Self.observerQueue)
        watcher.setEventHandler { [weak self, weak watcher] in
            guard !CloudEgressSocketIO.peerIsQuiet(observer) else { return }
            self?.cancel()
            watcher?.cancel()
        }
        watcher.setCancelHandler {
            Darwin.close(observer)
            drained.signal()
        }
        watcher.activate()
        return (watcher, drained)
    }

    private static let routes: [UInt8: CloudEgressRoute] = [
        1: .openAIModels, 2: .openAIChat, 3: .openAIResponses,
        4: .anthropicModels, 5: .anthropicMessages,
        6: .geminiModels, 7: .geminiChat, 8: .groqModels, 9: .groqChat
    ]
}

private struct CloudEgressSocketIO {
    let fd: Int32
    let cancellation: CloudEgressCancellation

    init(fd: Int32, cancellation: CloudEgressCancellation) throws {
        self.fd = fd
        self.cancellation = cancellation
        let flags = fcntl(fd, F_GETFL)
        var noSignal: Int32 = 1
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0,
              setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw POSIXError(.EIO)
        }
    }

    func checkPeer() throws {
        guard Self.peerIsQuiet(fd), !cancellation.isCancelled else { throw CancellationError() }
    }

    static func peerIsQuiet(_ descriptor: Int32) -> Bool {
        var state = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        var ready: Int32
        repeat { ready = poll(&state, 1, 0) } while ready < 0 && errno == EINTR
        return ready == 0
    }

    func readExactly(_ length: Int, deadline: ContinuousClock.Instant) throws -> Data {
        var data = Data(count: length)
        if length == 0 { return data }
        try data.withUnsafeMutableBytes { bytes in
            try transfer(bytes.count, events: Int16(POLLIN), deadline: deadline) { offset in
                Darwin.read(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
            }
        }
        return data
    }

    func write(_ data: Data, deadline: ContinuousClock.Instant) throws {
        try data.withUnsafeBytes { bytes in
            try transfer(bytes.count, events: Int16(POLLOUT), deadline: deadline) { offset in
                Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
            }
        }
    }

    private func transfer(
        _ length: Int, events: Int16, deadline: ContinuousClock.Instant, operation: (Int) -> Int
    ) throws {
        var offset = 0
        while offset < length {
            guard !cancellation.isCancelled else { throw CancellationError() }
            guard ContinuousClock.now < deadline else { throw CloudEgressTransportError.timedOut }
            var state = pollfd(fd: fd, events: events, revents: 0)
            let ready = poll(&state, 1, 25)
            if ready < 0 && errno == EINTR { continue }
            guard ready >= 0, state.revents & Int16(POLLNVAL) == 0 else { throw POSIXError(.EIO) }
            if ready == 0 { continue }
            guard !cancellation.isCancelled else { throw CancellationError() }
            guard ContinuousClock.now < deadline else { throw CloudEgressTransportError.timedOut }
            let count = operation(offset)
            if count < 0 && [EINTR, EAGAIN, EWOULDBLOCK].contains(errno) { continue }
            guard count > 0 else { throw POSIXError(.EPIPE) }
            offset += count
        }
    }
}

private final class CloudEgressSocketWriter {
    private enum State { case head, body, ended, failed }
    private var state = State.head
    private let io: CloudEgressSocketIO
    private let deadline: ContinuousClock.Instant

    init(io: CloudEgressSocketIO, deadline: ContinuousClock.Instant) {
        self.io = io
        self.deadline = deadline
    }

    func receive(_ event: CloudEgressResponseEvent) throws {
        do {
            try write(event)
        } catch {
            state = .failed
            throw error
        }
    }

    private func write(_ event: CloudEgressResponseEvent) throws {
        switch (state, event) {
        case (.head, .head(let status, let type)):
            guard (200...599).contains(status), !(300...399).contains(status) else { throw CloudEgressResponseError.invalidFraming }
            let media: UInt8
            switch type {
            case .none: media = 0
            case .json: media = 1
            case .eventStream: media = 2
            }
            try io.write(Data([1, 0, 0, 0, 3, UInt8(status >> 8), UInt8(truncatingIfNeeded: status), media]), deadline: deadline)
            state = .body
        case (.body, .body(let data)):
            guard (1...16384).contains(data.count) else { throw CloudEgressResponseError.limit }
            try io.write(Data([2, 0, 0, UInt8(data.count >> 8), UInt8(truncatingIfNeeded: data.count)]), deadline: deadline)
            try io.write(data, deadline: deadline)
        case (.body, .end):
            try io.write(Data([3, 0, 0, 0, 0]), deadline: deadline)
            state = .ended
        default:
            throw CloudEgressResponseError.invalidFraming
        }
    }
}
