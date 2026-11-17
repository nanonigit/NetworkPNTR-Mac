import Darwin
import Foundation

/// Owns one duplicate descriptor. Cancel only shuts it down; finish closes under
/// the same lock, so cancel can never act on a recycled descriptor number.
final class BackendUploadSocket: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptor: Int32?
    private var cancelled = false
    init(owning descriptor: Int32) { self.descriptor = descriptor }
    deinit { finish() }
    var isFinished: Bool { lock.lock(); defer { lock.unlock() }; return descriptor == nil }
    @discardableResult func cancel() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let interrupted = descriptor != nil && !cancelled
        cancelled = true
        if let descriptor { _ = shutdown(descriptor, SHUT_RDWR) }
        return interrupted
    }
    func finish() {
        lock.lock(); defer { lock.unlock() }
        if let descriptor { Darwin.close(descriptor); self.descriptor = nil }
    }
    func validateCompletion() throws {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { throw CancellationError() }
        guard descriptor == nil else { throw RuntimeError.integrity("unfinished upload worker") }
    }
    func checkedDescriptor() throws -> Int32 {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { throw CancellationError() }
        guard let descriptor else { throw RuntimeError.integrity("closed upload connection") }
        return descriptor
    }
}

enum BackendUploadExchange {
    /// Finite full-duplex exchange. Reader buffers are bounded independently of file size.
    static func exchange(socket: BackendUploadSocket, preamble: Data, header: Data, plan: ChatMultipartPlan, timeout: Duration = .seconds(300), progress: BackendUploadProgressHandler? = nil) throws -> BackendHTTPResponse {
        defer { socket.finish() }
        let descriptor = try socket.checkedDescriptor()
        let flags = fcntl(descriptor, F_GETFL)
        var noSignal: Int32 = 1
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0,
              setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size)) == 0 else { throw POSIXError(.EIO) }
        guard preamble.count <= 256, header.count <= 32768, timeout > .zero else { throw RuntimeError.integrity("upload exchange bounds") }
        let reporter = try BackendUploadProgressReporter(totalBodyBytes: plan.contentLength, progress: progress)
        let body = ChatMultipartBody(plan: plan)
        defer { body.close() }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        let expected = Int64(preamble.count + header.count) + plan.contentLength
        var outbound = preamble + header, offset = 0, written: Int64 = 0
        var response = Data(), responseStatus: Int?, responseStarted = false
        var writeError: POSIXError?
        var buffer = [UInt8](repeating: 0, count: 16384)
        while true {
            _ = try socket.checkedDescriptor()
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw RuntimeError.timeout("attachment transfer") }
            if !responseStarted, writeError == nil, offset == outbound.count, written < expected {
                guard let bytes = try body.read() else { throw RuntimeError.integrity("attachment body length") }
                outbound = bytes; offset = 0
            }
            let canWrite = !responseStarted && writeError == nil && offset < outbound.count
            var state = pollfd(fd: descriptor, events: Int16(POLLIN) | (canWrite ? Int16(POLLOUT) : 0), revents: 0)
            let ready = poll(&state, 1, 50)
            if ready < 0, errno == EINTR { continue }
            _ = try socket.checkedDescriptor()
            guard ready >= 0, state.revents & Int16(POLLNVAL) == 0 else { throw POSIXError(.EIO) }
            if state.revents & Int16(POLLIN | POLLHUP | POLLERR) != 0 {
                let count = Darwin.read(descriptor, &buffer, buffer.count)
                if count < 0, [EINTR,EAGAIN,EWOULDBLOCK].contains(errno) { continue }
                guard count >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                if count == 0 {
                    if response.isEmpty, let writeError { throw writeError }
                    guard responseStatus != nil, written == expected || responseStatus! >= 300 else { throw BackendAPIError.invalidResponse }
                    return try BackendHTTPResponse.parse(response)
                }
                guard count <= 4 * 1024 * 1024 - response.count else { throw RuntimeError.integrity("attachment response size") }
                response.append(contentsOf: buffer.prefix(count))
                if responseStatus == nil {
                    responseStatus = try statusIfComplete(response)
                    if let status = responseStatus {
                        guard status >= 300 || written == expected else { throw RuntimeError.integrity("premature attachment success") }
                        responseStarted = true
                        _ = shutdown(descriptor, SHUT_WR)
                    }
                }
                if let complete = try framedResponseIfComplete(response) { return complete }
            }
            if !responseStarted, canWrite, state.revents & Int16(POLLOUT) != 0 {
                let sent = outbound.withUnsafeBytes { bytes in
                    Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                }
                if sent < 0, [EINTR,EAGAIN,EWOULDBLOCK].contains(errno) { continue }
                _ = try socket.checkedDescriptor()
                if sent < 0 {
                    // A peer can reject the body and reset while its response is in flight.
                    // Stop writes, then drain its framed response before reporting the error.
                    writeError = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    _ = shutdown(descriptor, SHUT_WR)
                    continue
                }
                guard sent > 0 else { throw POSIXError(.EIO) }
                offset += sent; written += Int64(sent)
                let bodyWritten = max(0, written - Int64(preamble.count + header.count))
                try reporter.record(sentBodyBytes: bodyWritten)
            }
        }
    }
    /// Completion is determined by HTTP framing, not socket EOF (which may reset).
    private static func framedResponseIfComplete(_ wire: Data) throws -> BackendHTTPResponse? {
        guard let end = wire.range(of: Data("\r\n\r\n".utf8)),
              let header = String(data: wire[..<end.lowerBound], encoding: .isoLatin1) else { return nil }
        var length: String?, transfer: String?
        for line in header.components(separatedBy: "\r\n").dropFirst() {
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex,
                  !line.hasPrefix(" "), !line.hasPrefix("\t") else { throw BackendAPIError.invalidResponse }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if name == "content-length" { guard length == nil else { throw BackendAPIError.invalidResponse }; length = value }
            if name == "transfer-encoding" { guard transfer == nil else { throw BackendAPIError.invalidResponse }; transfer = value }
        }
        guard length == nil || transfer == nil else { throw BackendAPIError.invalidResponse }
        if let length {
            guard !length.isEmpty, length.utf8.allSatisfy({ (48...57).contains($0) }),
                  let size = Int(length), size <= 4 * 1024 * 1024 - end.upperBound else { throw BackendAPIError.invalidResponse }
            guard wire.count - end.upperBound >= size else { return nil }
            return try BackendHTTPResponse.parse(wire)
        }
        guard let transfer else { return nil } // Close-delimited bodies still need EOF.
        guard transfer.lowercased() == "chunked" else { throw BackendAPIError.invalidResponse }
        var cursor = end.upperBound
        func line() throws -> String? {
            guard let stop = wire.range(of: Data("\r\n".utf8), in: cursor..<wire.count) else {
                guard wire.count - cursor <= 8192 else { throw BackendAPIError.invalidResponse }
                return nil
            }
            guard stop.lowerBound - cursor <= 8192,
                  let value = String(data: wire[cursor..<stop.lowerBound], encoding: .ascii) else { throw BackendAPIError.invalidResponse }
            cursor = stop.upperBound
            return value
        }
        while true {
            guard let text = try line() else { return nil }
            let sizeText = text.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)[0]
            guard !sizeText.isEmpty, sizeText.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
                  let size = Int(sizeText, radix: 16), size <= 4 * 1024 * 1024 else { throw BackendAPIError.invalidResponse }
            if size == 0 {
                while true {
                    guard let trailer = try line() else { return nil }
                    if trailer.isEmpty { return try BackendHTTPResponse.parse(wire) }
                }
            }
            guard wire.count - cursor >= size + 2 else { return nil }
            guard wire[cursor + size..<cursor + size + 2] == Data("\r\n".utf8) else { throw BackendAPIError.invalidResponse }
            cursor += size + 2
        }
    }
    private static func statusIfComplete(_ wire: Data) throws -> Int? {
        guard let end = wire.range(of: Data("\r\n\r\n".utf8)) else {
            guard wire.count <= 65536 else { throw BackendAPIError.invalidResponse }
            return nil
        }
        guard end.lowerBound <= 65536,
              let header = String(data: wire[..<end.lowerBound], encoding: .isoLatin1),
              let line = header.components(separatedBy: "\r\n").first else { throw BackendAPIError.invalidResponse }
        let fields = line.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 2, ["HTTP/1.0","HTTP/1.1"].contains(fields[0]), fields[1].count == 3,
              let status = Int(fields[1]), (200...599).contains(status) else { throw BackendAPIError.invalidResponse }
        return status
    }
}
