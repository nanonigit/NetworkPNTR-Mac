import ArtexCloudTLS
import Foundation
import Network
import Synchronization

final class CloudEgressCancellation: Sendable {
    private let state = Mutex(false)
    var isCancelled: Bool { state.withLock { $0 } }
    func cancel() { state.withLock { $0 = true } }
}

enum CloudEgressTransportError: Error, Equatable {
    case mismatchedTarget
    case connectionFailed
    case transferFailed
    case timedOut
    case responseLimit
}

/// A single synchronous TLS exchange. Call on an owned broker worker.
enum CloudEgressTransport {
    private final class Callbacks {
        let cancellation: CloudEgressCancellation
        let receive: (Data) throws -> Void
        var failure: (any Error)?

        init(cancellation: CloudEgressCancellation, receive: @escaping (Data) throws -> Void) {
            self.cancellation = cancellation
            self.receive = receive
        }
    }

    static func exchange(
        _ request: CloudEgressRequest,
        at destination: CloudEgressDestination,
        cancellation: CloudEgressCancellation,
        receive: @escaping (Data) throws -> Void
    ) throws {
        guard !cancellation.isCancelled else { throw CancellationError() }
        guard request.route.hostname == destination.hostname,
              case .hostPort(let host, .https) = destination.endpoint else {
            throw CloudEgressTransportError.mismatchedTarget
        }
        let numericIP: String
        switch host {
        case .ipv4(let address): numericIP = address.debugDescription
        case .ipv6(let address): numericIP = address.debugDescription
        default: throw CloudEgressTransportError.mismatchedTarget
        }

        let callbacks = Callbacks(cancellation: cancellation, receive: receive)
        let owner = Unmanaged.passRetained(callbacks)
        defer { owner.release() }
        let context = owner.toOpaque()
        let result = destination.hostname.withCString { hostname in
            numericIP.withCString { address in
                var options = artx_cloud_options(
                    hostname: hostname, numeric_ip: address, port: 443,
                    connect_timeout_ms: 10_000, total_timeout_ms: 120_000,
                    maximum_response_bytes: 16 * 1024 * 1024
                )
                return request.header.withUnsafeBytes { header in
                    request.body.withUnsafeBytes { body in
                        artx_cloud_tls_exchange(
                            &options, header.bindMemory(to: UInt8.self).baseAddress, header.count,
                            body.bindMemory(to: UInt8.self).baseAddress, body.count,
                            { context in
                                let callback = Unmanaged<Callbacks>.fromOpaque(context!).takeUnretainedValue()
                                return callback.cancellation.isCancelled ? 1 : 0
                            }, { context, bytes, count in
                                let callback = Unmanaged<Callbacks>.fromOpaque(context!).takeUnretainedValue()
                                do {
                                    try callback.receive(Data(bytes: bytes!, count: count))
                                    return 0
                                } catch {
                                    callback.failure = error
                                    return 1
                                }
                            }, context
                        )
                    }
                }
            }
        }
        switch result {
        case ARTX_CLOUD_OK: return
        case ARTX_CLOUD_CANCELLED: throw CancellationError()
        case ARTX_CLOUD_TIMED_OUT: throw CloudEgressTransportError.timedOut
        case ARTX_CLOUD_RESPONSE_LIMIT: throw CloudEgressTransportError.responseLimit
        case ARTX_CLOUD_CONNECT_FAILED: throw CloudEgressTransportError.connectionFailed
        case ARTX_CLOUD_SINK_ABORTED: throw callbacks.failure ?? CloudEgressTransportError.transferFailed
        default: throw CloudEgressTransportError.transferFailed
        }
    }
}
