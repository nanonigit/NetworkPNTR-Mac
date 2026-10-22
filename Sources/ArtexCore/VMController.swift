import Foundation
import Observation
import Virtualization

@MainActor @Observable public final class VMController: NSObject, VZVirtualMachineDelegate {
    public private(set) var state: LifecycleState = .idle
    public private(set) var guestReady = false
    public private(set) var lastError: String?
    public private(set) var guestLog = ""
    @ObservationIgnored private var machine: VZVirtualMachine?
    @ObservationIgnored private var input: Pipe?
    @ObservationIgnored private var output: FileHandle?
    @ObservationIgnored private var poller: Task<Void, Never>?
    @ObservationIgnored private var logURL: URL?
    public var mayStart: Bool { state.canStart && machine == nil }
    public var hasMachine: Bool { machine != nil }
    public func start(artifacts directory: URL, logs: URL, readinessTimeout: Duration = .seconds(60)) async throws {
        guard mayStart else { throw RuntimeError.invalidTransition(state.rawValue, "starting") }
        try state.transition(to: .starting)
        lastError = nil; guestReady = false; guestLog = ""
        do {
            guard VZVirtualMachine.isSupported else { throw RuntimeError.unsupported }
            let manifest = try GuestArtifacts.load(from: directory)
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            let log = logs.appendingPathComponent("guest-" + UUID().uuidString + ".log")
            guard FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
            logURL = log
            let handle = try FileHandle(forWritingTo: log)
            output = handle
            let pipe = Pipe(); input = pipe
            let configuration = try VMConfiguration.make(kernel: directory.appendingPathComponent(manifest.kernel), initramfs: directory.appendingPathComponent(manifest.initramfs), input: pipe.fileHandleForReading, output: handle)
            try configuration.validate()
            let vm = VZVirtualMachine(configuration: configuration)
            vm.delegate = self; machine = vm
            try await startMachine(vm)
            try state.transition(to: .running)
            poller = Task { [weak self] in
                let deadline = ContinuousClock.now.advanced(by: readinessTimeout)
                while ContinuousClock.now < deadline {
                    guard !Task.isCancelled, let self, self.machine != nil else { return }
                    self.refreshLog()
                    if self.guestReady { return }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard !Task.isCancelled, let self, !self.guestReady else { return }
                self.fail(RuntimeError.timeout("guest readiness"))
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
        do {
            // Fixed management token interpreted by our minimal guest init; never a shell command.
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
        guestLog = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
        guestReady = guestLog.contains("ARTEX_MAC_GUEST_READY")
    }
    private func fail(_ error: Error) { lastError = error.localizedDescription; if state != .failed { try? state.transition(to: .failed) } }
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
    private func releaseResources() {
        poller?.cancel(); poller = nil; machine = nil
        try? output?.close(); output = nil
        try? input?.fileHandleForReading.close(); try? input?.fileHandleForWriting.close(); input = nil
    }
}
