import Darwin
import Foundation

package typealias GuestLogBatchReceiver = @MainActor @Sendable ([GuestLogEntry]) throws -> Bool

struct GuestLogSSEDecoder {
    private static let headerEnd = Data([13, 10, 13, 10])
    private static let headerLimit = 16 * 1024
    private static let eventLimit = 256 * 1024
    private var buffer = Data()
    private var opened = false
    private var event: Data?

    mutating func consume(_ bytes: Data) throws -> [GuestLogEntry] {
        buffer.append(bytes)
        if !opened {
            guard let end = buffer.range(of: Self.headerEnd) else {
                guard buffer.count <= Self.headerLimit else { throw BackendAPIError.invalidResponse }
                return []
            }
            guard buffer.distance(from: buffer.startIndex, to: end.upperBound) <= Self.headerLimit,
                  let header = String(data: buffer[..<end.lowerBound], encoding: .isoLatin1) else {
                throw BackendAPIError.invalidResponse
            }
            try Self.validate(header: header)
            buffer.removeSubrange(..<end.upperBound)
            opened = true
        }

        var rows: [GuestLogEntry] = []
        while let end = buffer.firstIndex(of: 10) {
            var line = buffer[..<end]
            buffer.removeSubrange(...end)
            if line.last == 13 { line.removeLast() }
            guard line.count <= Self.eventLimit else { throw BackendAPIError.invalidResponse }
            if line.isEmpty {
                if let event {
                    let row = try BackendJSONCoding.decode(GuestLogEntry.self, from: event)
                    guard row.seq > 0, (row.dbId ?? 1) > 0 else { throw BackendAPIError.invalidResponse }
                    rows.append(row)
                    self.event = nil
                }
            } else if line.first != 58 {
                guard line.starts(with: "data:".utf8), event == nil else { throw BackendAPIError.invalidResponse }
                let payload = line.dropFirst(5)
                event = Data(payload.first == 32 ? payload.dropFirst() : payload)
            }
        }
        guard buffer.count <= Self.eventLimit else { throw BackendAPIError.invalidResponse }
        return rows
    }

    private static func validate(header: String) throws {
        let lines = header.components(separatedBy: "\r\n")
        let statusLine = lines[0].split(separator: " ")
        guard statusLine.count >= 2, ["HTTP/1.0", "HTTP/1.1"].contains(statusLine[0]),
              statusLine[1].count == 3, let status = Int(statusLine[1]), (200...599).contains(status) else {
            throw BackendAPIError.invalidResponse
        }
        guard status == 200 else { throw BackendAPIError.status(status) }
        var contentType: String?
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex, !line.hasPrefix(" "), !line.hasPrefix("\t") else {
                throw BackendAPIError.invalidResponse
            }
            switch line[..<colon].lowercased() {
            case "content-length", "transfer-encoding":
                throw BackendAPIError.invalidResponse
            case "content-type":
                guard contentType == nil else { throw BackendAPIError.invalidResponse }
                contentType = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces).lowercased()
            default:
                break
            }
        }
        guard contentType == "text/event-stream" else { throw BackendAPIError.invalidResponse }
    }
}

enum GuestLogSSEExchange {
    static func stream(socket: BackendUploadSocket, request: Data, timeout: Duration = .seconds(45),
                       receive: @escaping GuestLogBatchReceiver) async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            do {
                try await Task.detached {
                    defer { socket.finish() }
                    try await read(socket: socket, request: request, timeout: timeout, receive: receive)
                }.value
            } catch {
                try Task.checkCancellation()
                try socket.validateCompletion()
                throw error
            }
            try Task.checkCancellation()
            try socket.validateCompletion()
        } onCancel: { socket.cancel() }
    }

    private static func read(socket: BackendUploadSocket, request: Data, timeout: Duration,
                             receive: @escaping GuestLogBatchReceiver) async throws {
        guard (1...16_384).contains(request.count), timeout > .zero else {
            throw BackendAPIError.invalidResponse
        }
        let descriptor = try socket.checkedDescriptor()
        let flags = fcntl(descriptor, F_GETFL)
        var noSignal: Int32 = 1
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0,
              setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw POSIXError(.EIO)
        }
        var deadline = ContinuousClock.now.advanced(by: timeout)
        func wait(_ events: Int16) throws {
            while ContinuousClock.now < deadline {
                _ = try socket.checkedDescriptor()
                var state = pollfd(fd: descriptor, events: events, revents: 0)
                let ready = poll(&state, 1, 50)
                if ready < 0 && errno == EINTR { continue }
                guard ready >= 0, state.revents & Int16(POLLNVAL) == 0 else { throw POSIXError(.EIO) }
                if ready > 0 { return }
            }
            throw RuntimeError.timeout("guest log stream")
        }
        try request.withUnsafeBytes { buffer in
            var written = 0
            while written < buffer.count {
                try wait(Int16(POLLOUT))
                let bytes = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: written), buffer.count - written)
                if bytes < 0 && [EINTR, EAGAIN, EWOULDBLOCK].contains(errno) { continue }
                guard bytes > 0 else { throw POSIXError(.EIO) }
                written += bytes
            }
        }
        var decoder = GuestLogSSEDecoder()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            try wait(Int16(POLLIN))
            let received = Darwin.read(descriptor, &buffer, buffer.count)
            if received < 0 && [EINTR, EAGAIN, EWOULDBLOCK].contains(errno) { continue }
            guard received >= 0 else { throw POSIXError(.EIO) }
            if received == 0 { return }
            deadline = ContinuousClock.now.advanced(by: timeout)
            let batch = try decoder.consume(Data(buffer.prefix(received)))
            _ = try socket.checkedDescriptor()
            if !batch.isEmpty {
                guard try await receive(batch) else { return }
            }
        }
    }
}
