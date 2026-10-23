import Darwin
import Foundation

enum BackendDownloadExchange {
    static func exchange(socket: BackendUploadSocket, preamble: Data, request: Data, expectedSize: Int64, timeout: Duration = .seconds(300)) throws -> BackendDownloadResult {
        defer { socket.finish() }
        let decoder = try BackendDownloadDigest(expectedSize: expectedSize)
        defer { decoder.cancel() }
        guard preamble.count <= 256, request.count <= 32768, !request.isEmpty, timeout > .zero else { throw BackendAPIError.invalidResponse }
        let descriptor = try socket.checkedDescriptor()
        let flags = fcntl(descriptor, F_GETFL)
        var noSignal: Int32 = 1
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0,
              setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size)) == 0 else { throw POSIXError(.EIO) }
        let outbound = preamble + request
        var offset = 0
        var buffer = [UInt8](repeating: 0, count: 65536)
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while true {
            _ = try socket.checkedDescriptor(); try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw RuntimeError.timeout("attachment download") }
            var state = pollfd(fd: descriptor, events: Int16(POLLIN) | (offset < outbound.count ? Int16(POLLOUT) : 0), revents: 0)
            let ready = poll(&state, 1, 50)
            if ready < 0 && errno == EINTR { continue }
            _ = try socket.checkedDescriptor()
            guard ready >= 0, state.revents & Int16(POLLNVAL) == 0 else { throw POSIXError(.EIO) }
            if state.revents & Int16(POLLIN | POLLHUP | POLLERR) != 0 {
                let n = Darwin.read(descriptor, &buffer, buffer.count)
                if n < 0 && [EINTR,EAGAIN,EWOULDBLOCK].contains(errno) { continue }
                guard n >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                if n == 0 { return try decoder.finish() }
                try decoder.consume(Data(buffer.prefix(n)))
                if decoder.isComplete { return try decoder.finish() }
            }
            if offset < outbound.count, state.revents & Int16(POLLOUT) != 0 {
                let n = outbound.withUnsafeBytes { bytes in
                    Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                }
                if n < 0 && [EINTR,EAGAIN,EWOULDBLOCK].contains(errno) { continue }
                _ = try socket.checkedDescriptor()
                guard n > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                offset += n
            }
        }
    }
}
