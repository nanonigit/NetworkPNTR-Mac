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
        timeout: Duration = .seconds(120),
        receive: @escaping (CloudEgressResponseEvent) throws -> Void
    ) throws {
        try frameResponse(receive: receive, stopAtBoundary: true) { consume in
            try exchangeRaw(request, at: destination, cancellation: cancellation, timeout: timeout, receive: consume)
            guard !cancellation.isCancelled else { throw CancellationError() }
        }
    }

    static func exchangeFromBroker(
        _ request: CloudEgressRequest,
        _ cancellation: CloudEgressCancellation,
        _ deadline: ContinuousClock.Instant,
        _ receive: @escaping (CloudEgressResponseEvent) throws -> Void
    ) throws {
        guard !cancellation.isCancelled else { throw CancellationError() }
        guard ContinuousClock.now < deadline else { throw CloudEgressTransportError.timedOut }
        let destinations = try request.route.destinations()
        let (ipv4, other) = destinations.reduce(into: ([CloudEgressDestination](), [CloudEgressDestination]())) {
            if case .hostPort(host: .ipv4, port: _) = $1.endpoint { $0.0.append($1) }
            else { $0.1.append($1) }
        }
        for destination in (ipv4 + other).prefix(4) {
            var startedResponse = false
            do {
                try exchange(request, at: destination, cancellation: cancellation, timeout: deadline - .now) { event in
                    startedResponse = true
                    try receive(event)
                }
                return
            } catch CloudEgressTransportError.connectionFailed where !startedResponse {
                // This result is issued only before the worker sends HTTP bytes.
                continue
            }
        }
        throw CloudEgressTransportError.connectionFailed
    }

    private static func exchangeRaw(
        _ request: CloudEgressRequest,
        at destination: CloudEgressDestination,
        cancellation: CloudEgressCancellation,
        timeout: Duration,
        receive: @escaping (Data) throws -> Void
    ) throws {
        guard !cancellation.isCancelled else { throw CancellationError() }
        guard timeout > .zero else { throw CloudEgressTransportError.timedOut }
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
        let budget = min(timeout, .seconds(120)).components
        let timeoutMilliseconds = UInt32(max(1, budget.seconds * 1_000 + budget.attoseconds / 1_000_000_000_000_000))
        let result = destination.hostname.withCString { hostname in
            numericIP.withCString { address in
                var options = artx_cloud_options(
                    hostname: hostname, numeric_ip: address, port: 443,
                    connect_timeout_ms: min(4_000, timeoutMilliseconds), total_timeout_ms: timeoutMilliseconds,
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
                                } catch is CloudEgressResponseBoundary {
                                    return 2
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
