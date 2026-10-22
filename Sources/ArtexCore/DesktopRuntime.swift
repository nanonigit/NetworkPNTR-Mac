import Darwin
import Foundation
import Observation

public struct ManagedRuntimePaths: Sendable {
    public let root: URL
    public var disk: URL { root.appendingPathComponent("state.ext4") }
    public var logs: URL { root.appendingPathComponent("Logs", isDirectory: true) }
    public init(root: URL) { self.root = root }
    public static var applicationDefault: Self {
        Self(root: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("com.nanonigit.artex-mac", isDirectory: true))
    }
    public func prepareDirectories() throws {
        for directory in [root, logs] {
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            }
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
            guard values.isDirectory == true, values.isSymbolicLink != true,
                  (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw RuntimeError.integrity("private application data directory") }
        }
    }
}

@MainActor @Observable public final class DesktopRuntime {
    public let controller = VMController()
    public private(set) var authentication: AuthenticationSession?
    public private(set) var isStarting = false
    public private(set) var error: String?
    public let paths: ManagedRuntimePaths
    @ObservationIgnored private let artifacts: URL
    @ObservationIgnored private let vault: any SessionVault
    @ObservationIgnored private var generation = UUID()
    public init(artifacts: URL, paths: ManagedRuntimePaths = .applicationDefault, vault: any SessionVault) {
        self.artifacts = artifacts; self.paths = paths; self.vault = vault
    }
    public func start() async {
        guard !isStarting, controller.mayStart else { return }
        isStarting = true; error = nil; authentication = nil
        let operation = UUID(); generation = operation
        defer { if generation == operation { isStarting = false } }
        do {
            try paths.prepareDirectories()
            _ = try PersistentGuestDisk.createIfMissing(at: paths.disk, byteCount: 2 * 1024 * 1024 * 1024)
            let provisioning = try GuestProvisioning.generate()
            try await controller.start(artifacts: artifacts, logs: paths.logs, readinessTimeout: .seconds(120), dataDisk: paths.disk, provisioning: provisioning)
            for _ in 0..<1300 {
                guard generation == operation, !Task.isCancelled else { return }
                if controller.guestReady || controller.state == .failed || controller.state == .stopped { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard generation == operation else { return }
            guard controller.guestReady else { throw RuntimeError.timeout(controller.lastError ?? "ARTEX backend startup") }
            let session = AuthenticationSession(client: BackendJSONClient(runtime: controller, provisioning: provisioning), vault: vault, setupToken: provisioning.setupToken)
            authentication = session
            await session.refresh()
        } catch {
            if generation == operation { self.error = error.localizedDescription }
        }
    }
    public func stop() async throws {
        generation = UUID(); isStarting = false; authentication = nil
        try await controller.stop()
    }
    public func forceStop() async throws {
        generation = UUID(); isStarting = false; authentication = nil
        try await controller.forceStop()
    }
}
