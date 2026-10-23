import Darwin
import Foundation
import Observation
import Virtualization

@MainActor @Observable public final class VMController: NSObject, VZVirtualMachineDelegate {
    public private(set) var state: LifecycleState = .idle
    public private(set) var guestReady = false
    public private(set) var lastError: String?
    public private(set) var guestLog = ""
    public private(set) var configuredCPUCount = 0
    @ObservationIgnored private var machine: VZVirtualMachine?
    @ObservationIgnored private var input: Pipe?
    @ObservationIgnored private var output: FileHandle?
    @ObservationIgnored private var poller: Task<Void, Never>?
    @ObservationIgnored private var logURL: URL?
    @ObservationIgnored private var backendConnections: [UUID: VZVirtioSocketConnection] = [:]
    @ObservationIgnored private var backendUploads: [UUID: BackendUploadSocket] = [:]
    @ObservationIgnored private var pendingConnections: [UUID: CheckedContinuation<UUID, Error>] = [:]
    public var mayStart: Bool { state.canStart && machine == nil }
    public var hasMachine: Bool { machine != nil }
    public func start(artifacts directory: URL, logs: URL, readinessTimeout: Duration = .seconds(60), dataDisk: URL? = nil, provisioning: GuestProvisioning? = nil) async throws {
        guard mayStart else { throw RuntimeError.invalidTransition(state.rawValue, "starting") }
        try state.transition(to: .starting)
        lastError = nil; guestReady = false; guestLog = ""
        do {
            guard VZVirtualMachine.isSupported else { throw RuntimeError.unsupported }
            let manifest = try GuestArtifacts.load(from: directory)
            guard (manifest.systemDisk == nil) == (dataDisk == nil), (manifest.systemDisk == nil) == (provisioning == nil) else {
                throw RuntimeError.integrity("backend provisioning and data disk")
            }
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            let log = logs.appendingPathComponent("guest-" + UUID().uuidString + ".log")
            guard FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
            logURL = log
            let handle = try FileHandle(forWritingTo: log)
            output = handle
            let pipe = Pipe(); input = pipe
            let configuration = try VMConfiguration.make(kernel: directory.appendingPathComponent(manifest.kernel), initramfs: directory.appendingPathComponent(manifest.initramfs), input: pipe.fileHandleForReading, output: handle, systemDisk: manifest.systemDisk.map { directory.appendingPathComponent($0) }, dataDisk: dataDisk, directRoot: manifest.bootMode == "rootDisk", cpuCount: manifest.cpuCount ?? 2)
            try configuration.validate()
            configuredCPUCount = configuration.cpuCount
            let vm = VZVirtualMachine(configuration: configuration)
            vm.delegate = self; machine = vm
            try await startMachine(vm)
            try state.transition(to: .running)
            poller = Task { [weak self] in
                var bootstrapSent = false
                let deadline = ContinuousClock.now.advanced(by: readinessTimeout)
                while !Task.isCancelled {
                    guard let self, self.machine != nil else { return }
                    self.refreshLog()
                    if self.state == .failed { return }
                    if !bootstrapSent, let provisioning, self.guestLog.contains("ARTEX_MAC_GUEST_BOOTSTRAP") {
                        do {
                            try pipe.fileHandleForWriting.write(contentsOf: Data(provisioning.serialBootstrap.utf8))
                            bootstrapSent = true
                        } catch { self.fail(error); return }
                    }
                    if !self.guestReady && ContinuousClock.now >= deadline {
                        self.fail(RuntimeError.timeout("guest readiness"))
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(self.guestReady ? 500 : 100))
                }
            }
        } catch {
            if let vm = machine, vm.canStop { try? await stopMachine(vm) }
            releaseResources()
            fail(error)
            throw error
        }
    }
    public func stop() async throws {
        guard state.canStop, let input else { throw RuntimeError.invalidTransition(state.rawValue, "stopping") }
        try state.transition(to: .stopping)
        cancelBackendUploads()
        do {
            // Bootstrap must complete before the guest can interpret management tokens.
            // Sending STOP into its credential reader would corrupt the bootstrap protocol.
            for _ in 0..<1300 {
                if guestReady || state == .stopped { break }
                if state == .failed { throw RuntimeError.timeout("guest initialization before shutdown") }
                try await Task.sleep(for: .milliseconds(100))
            }
            if state == .stopped { return }
            guard guestReady else { throw RuntimeError.timeout("guest initialization before shutdown") }
            // Fixed management token interpreted by our guest init; never a shell command.
            try input.fileHandleForWriting.write(contentsOf: Data("ARTEX_CONTROL_STOP\n".utf8))
            for _ in 0..<100 {
                if state == .stopped { return }
                if state == .failed { throw RuntimeError.timeout("guest shutdown") }
                try await Task.sleep(for: .milliseconds(100))
            }
            throw RuntimeError.timeout("guest shutdown")
        } catch { fail(error); throw error }
    }
    public func forceStop() async throws {
        guard let vm = machine else { return }
        cancelBackendUploads()
        do {
            try await stopMachine(vm)
            refreshLog(); releaseResources()
            if state != .stopped { try state.transition(to: .stopped) }
            guestReady = false
        } catch { fail(error); throw error }
    }
    nonisolated public func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        Task { @MainActor [weak self] in self?.completeStop() }
    }
    private func completeStop() {
        refreshLog(); releaseResources()
        if state != .stopped { try? state.transition(to: .stopped) }
        guestReady = false
    }
    nonisolated public func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.refreshLog(); self.releaseResources(); self.fail(error)
        }
    }
    private func refreshLog() {
        guard let logURL, let handle = try? FileHandle(forReadingFrom: logURL) else { return }
        defer { try? handle.close() }
        let length = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: length > 65536 ? length - 65536 : 0)
        guestLog = String(decoding: (try? handle.read(upToCount: 65536)) ?? Data(), as: UTF8.self)
        if guestLog.contains("Kernel panic") || guestLog.contains("Internal error: Oops") { guestReady = false; fail(RuntimeError.integrity("guest kernel panic")); return }
        guestReady = guestReady || guestLog.contains("ARTEX_MAC_GUEST_READY")
        if let failure = guestLog.components(separatedBy: .newlines).last(where: { $0.hasPrefix("ARTEX_MAC_GUEST_ERROR stage=") }) {
            guestReady = false
            fail(RuntimeError.integrity(String(failure.prefix(160))))
        }
    }
    private func fail(_ error: Error) { cancelBackendUploads(); lastError = error.localizedDescription; if state != .failed { try? state.transition(to: .failed) } }
    // Completion-handler calls stay on our MainActor. Older SDK async overlays treat
    // VZVirtualMachine as a non-Sendable value crossing isolation during `await`.
    private func startMachine(_ vm: VZVirtualMachine) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            vm.start { result in continuation.resume(with: result) }
        }
    }
    private func stopMachine(_ vm: VZVirtualMachine) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            vm.stop { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
    /// Bounded HTTP exchange for backend acceptance probes. Streaming UI integration is a separate pending gate.
    public func probeBackend(request: Data, provisioning: GuestProvisioning, rejectTransport: Bool = false) async throws -> Data {
        guard guestReady, state == .running else { throw RuntimeError.integrity("backend not ready") }
        let identifier = try await connectBackend()
        defer { backendConnections.removeValue(forKey: identifier)?.close() }
        guard let connection = backendConnections[identifier] else { throw RuntimeError.integrity("closed backend connection") }
        let descriptor = dup(connection.fileDescriptor)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        let credential = rejectTransport ? String(repeating: "0", count: 64) : provisioning.transportToken
        let bytes = Data(("ARTEX_VSOCK_1 " + credential + "\n").utf8) + request
        return try await Task.detached {
            defer { Darwin.close(descriptor) }
            return try BackendSocketExchange.exchange(descriptor: descriptor, request: bytes)
        }.value
    }
    /// Dedicated multipart exchange; payload files never become a shared VM directory.
    func uploadBackend(plan: ChatMultipartPlan, header: Data, provisioning: GuestProvisioning) async throws -> BackendHTTPResponse {
        try Task.checkCancellation()
        guard guestReady, state == .running else { throw RuntimeError.integrity("backend not ready") }
        let identifier = try await connectBackend()
        defer {
            backendUploads.removeValue(forKey: identifier)?.finish()
            backendConnections.removeValue(forKey: identifier)?.close()
        }
        try Task.checkCancellation()
        guard guestReady, state == .running,
              let connection = backendConnections[identifier] else { throw RuntimeError.integrity("closed upload connection") }
        let descriptor = dup(connection.fileDescriptor)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        let socket = BackendUploadSocket(owning: descriptor)
        backendUploads[identifier] = socket
        guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else { throw POSIXError(.EIO) }
        let preamble = Data(("ARTEX_VSOCK_1 " + provisioning.transportToken + "\n").utf8)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let response = try await Task.detached {
                try BackendUploadExchange.exchange(socket: socket, preamble: preamble, header: header, plan: plan)
            }.value
            try Task.checkCancellation()
            try socket.validateCompletion()
            guard guestReady, state == .running, backendUploads[identifier] === socket else { throw CancellationError() }
            return response
        } onCancel: { socket.cancel() }
    }
    private func cancelBackendUploads() {
        for socket in backendUploads.values { socket.cancel() }
    }
    private func connectBackend() async throws -> UUID {
        guard let device = machine?.socketDevices.first as? VZVirtioSocketDevice else { throw RuntimeError.integrity("backend vsock device") }
        let identifier = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                pendingConnections[identifier] = continuation
                device.connect(toPort: 8787) { [weak self] result in
                    // VZVirtualMachine's default queue invokes all callbacks on the main queue.
                    MainActor.assumeIsolated {
                        guard let self, let pending = self.pendingConnections.removeValue(forKey: identifier) else {
                            if case let .success(connection) = result { connection.close() }
                            return
                        }
                        switch result {
                        case let .success(connection): self.backendConnections[identifier] = connection; pending.resume(returning: identifier)
                        case let .failure(error): pending.resume(throwing: error)
                        }
                    }
                }
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(10))
                    self?.pendingConnections.removeValue(forKey: identifier)?.resume(throwing: RuntimeError.timeout("backend connection"))
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.pendingConnections.removeValue(forKey: identifier)?.resume(throwing: CancellationError())
            }
        }
    }
    private func releaseResources() {
        cancelBackendUploads(); backendUploads.removeAll()
        for continuation in pendingConnections.values { continuation.resume(throwing: RuntimeError.integrity("VM connection closed")) }
        pendingConnections.removeAll()
        for connection in backendConnections.values { connection.close() }
        backendConnections.removeAll()
        poller?.cancel(); poller = nil; machine = nil
        try? output?.close(); output = nil
        try? input?.fileHandleForReading.close(); try? input?.fileHandleForWriting.close(); input = nil
    }
}
