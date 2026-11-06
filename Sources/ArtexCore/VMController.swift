import Darwin
import Foundation
import Observation
import Virtualization

@MainActor @Observable public final class VMController: NSObject, VZVirtualMachineDelegate {
    public private(set) var state: LifecycleState = .idle
    public private(set) var guestReady = false
    private var runtimeFeatures = GuestRuntimeFeatures()
    /// A ready boot lease; stop/failure invalidates it before another boot can be used.
    public var trafficBlobExportGeneration: UUID? { canExportTrafficBlobs ? evidenceEpoch : nil }
    public var canExportTrafficBlobs: Bool {
        runtimeFeatures.allowsTrafficBlobExport(state: state, ready: guestReady, hasMachine: machine != nil)
    }
    public private(set) var lastError: String?
    public private(set) var failure: AppErrorMessage?
    public private(set) var guestLog = ""
    public private(set) var configuredCPUCount = 0
    public private(set) var lastStopInterruptedTransferCount = 0
    @ObservationIgnored private var machine: VZVirtualMachine?
    @ObservationIgnored private var input: Pipe?
    @ObservationIgnored private var output: FileHandle?
    @ObservationIgnored private var poller: Task<Void, Never>?
    @ObservationIgnored private var logURL: URL?
    @ObservationIgnored private var backendConnections: [UUID: VZVirtioSocketConnection] = [:]
    @ObservationIgnored private var backendUploads: [UUID: BackendUploadSocket] = [:]
    @ObservationIgnored private var cloudEgressListener: CloudEgressVMListener?
    private var forceStopping = false
    private var cooperativeStopping = false
    @ObservationIgnored private var evidenceEpoch = UUID()
    #if DEBUG
    @ObservationIgnored package var evidenceCancellationProbe: EvidenceCancellationProbe?
    @ObservationIgnored package var trafficBlobCancellationProbe: TrafficBlobCancellationProbe?
    #endif
    @ObservationIgnored private var pendingConnections: [UUID: CheckedContinuation<UUID, Error>] = [:]
    public var mayStart: Bool { state.canStart && machine == nil && !forceStopping && !cooperativeStopping }
    public var hasMachine: Bool { machine != nil }
    package func enableCloudEgress() throws {
        try enableCloudEgress(upstream: CloudEgressTransport.exchangeFromBroker)
    }

    #if DEBUG
    package func enableCloudEgress(fixture: CloudEgressVMFixture) throws {
        guard cloudEgressListener == nil else {
            throw RuntimeError.integrity("cloud egress fixture requires an unused listener")
        }
        try enableCloudEgress(upstream: fixture.exchange)
    }
    #endif

    private func enableCloudEgress(upstream: @escaping CloudEgressSocketSession.Upstream) throws {
        guard state == .running, guestReady, !forceStopping, !cooperativeStopping,
              let device = machine?.socketDevices.first as? VZVirtioSocketDevice else {
            throw RuntimeError.integrity("cloud egress requires a ready guest")
        }
        guard cloudEgressListener == nil else { return }
        let listener = CloudEgressVMListener(device: device, upstream: upstream)
        cloudEgressListener = listener
        listener.start()
    }

    private func disableCloudEgress() {
        cloudEgressListener?.stop()
        cloudEgressListener = nil
    }
    public func start(artifacts directory: URL, logs: URL, readinessTimeout: Duration = .seconds(60), dataDisk: URL? = nil, provisioning: GuestProvisioning? = nil) async throws {
        guard mayStart else { throw RuntimeError.invalidTransition(state.rawValue, "starting") }
        runtimeFeatures = GuestRuntimeFeatures()
        try state.transition(to: .starting)
        lastError = nil; failure = nil; guestReady = false; guestLog = ""; lastStopInterruptedTransferCount = 0
        do {
            guard VZVirtualMachine.isSupported else { throw RuntimeError.unsupported }
            let manifest = try GuestArtifacts.load(from: directory)
            runtimeFeatures = GuestRuntimeFeatures(trafficBlobExportDeclared: manifest.declaresTrafficBlobExport)
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
        guard state.canStop, !forceStopping, !cooperativeStopping, let input else {
            throw RuntimeError.invalidTransition(state.rawValue, "stopping")
        }
        cooperativeStopping = true
        defer { cooperativeStopping = false }
        try state.transition(to: .stopping)
        disableCloudEgress()
        lastStopInterruptedTransferCount = cancelBackendUploads()
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
        guard let vm = machine, !forceStopping else { return }
        forceStopping = true
        defer { forceStopping = false }
        if state == .running { try state.transition(to: .stopping) }
        disableCloudEgress()
        lastStopInterruptedTransferCount = cancelBackendUploads()
        do {
            try await stopMachine(vm)
            refreshLog(); releaseResources()
            if state != .stopped { try state.transition(to: .stopped) }
            guestReady = false
        } catch { fail(error); throw error }
    }
    nonisolated public func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        let stopped = ObjectIdentifier(virtualMachine)
        Task { @MainActor [weak self] in
            guard let self, self.machine.map(ObjectIdentifier.init) == stopped else { return }
            self.completeStop()
        }
    }
    private func completeStop() {
        refreshLog(); releaseResources()
        if state != .stopped { try? state.transition(to: .stopped) }
        guestReady = false
    }
    nonisolated public func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        let stopped = ObjectIdentifier(virtualMachine)
        Task { @MainActor [weak self] in
            guard let self, self.machine.map(ObjectIdentifier.init) == stopped else { return }
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
    private func fail(_ error: Error) { runtimeFeatures = GuestRuntimeFeatures(); disableCloudEgress(); cancelBackendUploads(); lastError = error.localizedDescription; failure = AppErrorMessage(error, fallback: .runtimeUIUnexpected); if state != .failed { try? state.transition(to: .failed) } }
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
    func uploadBackend(plan: ChatMultipartPlan, header: Data, provisioning: GuestProvisioning, progress: BackendUploadProgressHandler? = nil) async throws -> BackendHTTPResponse {
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
                try BackendUploadExchange.exchange(socket: socket, preamble: preamble, header: header, plan: plan, progress: progress)
            }.value
            try Task.checkCancellation()
            try socket.validateCompletion()
            guard guestReady, state == .running, backendUploads[identifier] === socket else { throw CancellationError() }
            return response
        } onCancel: { socket.cancel() }
    }
    /// A bounded digest stream on an owned transfer socket, with the same stop lease as uploads.
    func downloadBackendDigest(request: Data, expectedSize: Int64, provisioning: GuestProvisioning) async throws -> BackendDownloadResult {
        try Task.checkCancellation()
        guard guestReady, state == .running else { throw RuntimeError.integrity("backend not ready") }
        let identifier = try await connectBackend()
        defer {
            backendUploads.removeValue(forKey: identifier)?.finish()
            backendConnections.removeValue(forKey: identifier)?.close()
        }
        try Task.checkCancellation()
        guard guestReady, state == .running,
              let connection = backendConnections[identifier] else { throw RuntimeError.integrity("closed download connection") }
        let descriptor = dup(connection.fileDescriptor)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        let socket = BackendUploadSocket(owning: descriptor)
        backendUploads[identifier] = socket
        guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else { throw POSIXError(.EIO) }
        let preamble = Data(("ARTEX_VSOCK_1 " + provisioning.transportToken + "\n").utf8)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let response = try await Task.detached {
                try BackendDownloadExchange.exchange(socket: socket, preamble: preamble, request: request, expectedSize: expectedSize)
            }.value
            try Task.checkCancellation()
            try socket.validateCompletion()
            guard guestReady, state == .running, backendUploads[identifier] === socket else { throw CancellationError() }
            return response
        } onCancel: { socket.cancel() }
    }
    func stageBackendEvidence(request: Data, manifest: any EvidenceBodyManifest, destination: EvidenceExportDestination, provisioning: GuestProvisioning) async throws -> EvidenceExportReceipt {
        try Task.checkCancellation()
        guard guestReady, state == .running else { throw RuntimeError.integrity("backend not ready") }
        let epoch = evidenceEpoch
        let identifier = try await connectBackend()
        defer {
            backendUploads.removeValue(forKey: identifier)?.finish()
            backendConnections.removeValue(forKey: identifier)?.close()
        }
        try Task.checkCancellation()
        guard guestReady, state == .running, evidenceEpoch == epoch,
              let connection = backendConnections[identifier] else { throw CancellationError() }
        let descriptor = dup(connection.fileDescriptor)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        let socket = BackendUploadSocket(owning: descriptor)
        backendUploads[identifier] = socket
        guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else { throw POSIXError(.EIO) }
        let preamble = Data(("ARTEX_VSOCK_1 " + provisioning.transportToken + "\n").utf8)
        #if DEBUG
        let cancellationProbe = evidenceCancellationProbe
        let blobCancellationProbe = trafficBlobCancellationProbe
        let blobTransfer = (manifest as? TrafficBlobDownload).flatMap { blob in
            blobCancellationProbe.map { TrafficBlobCancellationProbe.Transfer(probe: $0, operationID: identifier, manifest: blob) }
        }
        #endif
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let response = try await Task.detached {
                #if DEBUG
                try TrafficBlobCancellationProbe.$current.withValue(blobTransfer) {
                    try EvidenceDownloadStaging.exchange(socket: socket, preamble: preamble, request: request, manifest: manifest, destination: destination)
                }
                #else
                try EvidenceDownloadStaging.exchange(socket: socket, preamble: preamble, request: request, manifest: manifest, destination: destination)
                #endif
            }.value
            do {
                try Task.checkCancellation()
                try socket.validateCompletion()
                guard guestReady, state == .running, evidenceEpoch == epoch, backendUploads[identifier] === socket else { throw CancellationError() }
                return EvidenceExportReceipt(response: response, validate: { [weak self] in
                    guard let self, self.guestReady, self.state == .running, self.evidenceEpoch == epoch else { throw CancellationError() }
                })
            } catch {
                try response.file?.discard()
                throw error
            }
        } onCancel: {
            #if DEBUG
            let interrupted = socket.cancel()
            if let finding = manifest as? FindingEvidenceDownload {
                cancellationProbe?.record(operationID: identifier, manifest: finding, interrupted: interrupted)
            } else if let blob = manifest as? TrafficBlobDownload {
                blobCancellationProbe?.recordCancellation(operationID: identifier, manifest: blob, interrupted: interrupted)
            }
            #else
            socket.cancel()
            #endif
        }
    }
    @discardableResult private func cancelBackendUploads() -> Int {
        evidenceEpoch = UUID()
        return backendUploads.values.reduce(0) { count, socket in count + (socket.cancel() ? 1 : 0) }
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
        disableCloudEgress()
        runtimeFeatures = GuestRuntimeFeatures()
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
