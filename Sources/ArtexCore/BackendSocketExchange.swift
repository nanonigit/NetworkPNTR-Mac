import Darwin
import Foundation

/// Finite JSON exchange on a VZ-owned descriptor duplicated by the caller.
/// Readiness must be polled: VZ sockets can be nonblocking even with SO_RCVTIMEO.
enum BackendSocketExchange {
    static func exchange(socket: BackendUploadSocket, request: Data) async throws -> Data {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let response: Data
            do {
                response = try await Task.detached {
                    defer { socket.finish() }
                    return try exchange(descriptor: socket.checkedDescriptor(), request: request)
                }.value
            } catch {
                // Shutdown can surface as an I/O error before the caller resumes.
                try Task.checkCancellation()
                try socket.validateCompletion()
                throw error
            }
            try Task.checkCancellation()
            try socket.validateCompletion()
            return response
        } onCancel: { socket.cancel() }
    }

    static func exchange(descriptor: Int32, request: Data) throws -> Data {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        func wait(_ events: Int16) throws {
            while ContinuousClock.now < deadline {
                var state = pollfd(fd: descriptor, events: events, revents: 0)
                let result = poll(&state, 1, 1000)
                if result < 0 && errno == EINTR { continue }
                guard result >= 0, state.revents & Int16(POLLNVAL) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                if result > 0 { return }
            }
            throw RuntimeError.timeout("backend response")
        }
        var noSignal: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size)) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        guard setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0,
              setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        try request.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                try wait(Int16(POLLOUT))
                let sent = Darwin.write(descriptor, base.advanced(by: offset), buffer.count - offset)
                if sent < 0 && [EINTR, EAGAIN, EWOULDBLOCK].contains(errno) { continue }
                guard sent > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                offset += sent
            }
        }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        while true {
            try wait(Int16(POLLIN))
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count < 0 && [EINTR, EAGAIN, EWOULDBLOCK].contains(errno) { continue }
            guard count >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            if count == 0 { return result }
            guard result.count + count <= 4 * 1024 * 1024 else { throw RuntimeError.integrity("JSON response size") }
            result.append(contentsOf: buffer.prefix(count))
        }
    }
}
