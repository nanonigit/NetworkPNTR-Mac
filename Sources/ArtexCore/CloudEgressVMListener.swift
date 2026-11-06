import Darwin
import Foundation
import Synchronization
import Virtualization

@MainActor
final class CloudEgressVMListener: NSObject, @preconcurrency VZVirtioSocketListenerDelegate {
    static let port: UInt32 = 8790
    private static let admission = CloudEgressAdmission()

    private let device: VZVirtioSocketDevice
    private let listener = VZVirtioSocketListener()
    private var running = false
    private var active: [UUID: (VZVirtioSocketConnection, CloudEgressSocketSession)] = [:]

    init(device: VZVirtioSocketDevice) {
        self.device = device
        super.init()
    }

    func start() {
        guard !running else { return }
        running = true
        listener.delegate = self
        device.setSocketListener(listener, forPort: Self.port)
    }

    func stop() {
        guard running else { return }
        running = false
        device.removeSocketListener(forPort: Self.port)
        listener.delegate = nil
        for (connection, session) in active.values {
            session.cancel()
            connection.close()
        }
        active.removeAll()
    }

    func listener(
        _ listener: VZVirtioSocketListener,
        shouldAcceptNewConnection connection: VZVirtioSocketConnection,
        from socketDevice: VZVirtioSocketDevice
    ) -> Bool {
        // The VM uses Virtualization's default main queue.
        let admission = Self.admission
        guard running, listener === self.listener, socketDevice === device,
              connection.destinationPort == Self.port, admission.acquire() else { return false }
        let fd = fcntl(connection.fileDescriptor, F_DUPFD_CLOEXEC, 0)
        guard fd >= 0 else { admission.release(); return false }
        let id = UUID()
        let session = CloudEgressSocketSession(owning: fd)
        active[id] = (connection, session)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            session.run()
            Task { @MainActor [weak self] in
                self?.active.removeValue(forKey: id)?.0.close()
                admission.release()
            }
        }
        return true
    }
}

/// Slots remain charged until workers exit, even if their VM has stopped
/// while system DNS resolution was in progress.
final class CloudEgressAdmission: Sendable {
    private let active = Mutex(0)
    private let limit: Int

    init(limit: Int = 4) { self.limit = limit }

    func acquire() -> Bool {
        active.withLock { count in
            guard count < limit else { return false }
            count += 1
            return true
        }
    }

    func release() { active.withLock { $0 -= 1 } }
}
