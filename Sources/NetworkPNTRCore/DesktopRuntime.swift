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
    public let mcp = MCPClientStore()
    public private(set) var authentication: AuthenticationSession?
    public private(set) var isStarting = false
    public private(set) var error: String?
    public private(set) var failure: AppErrorMessage?
    public let paths: ManagedRuntimePaths
    #if DEBUG
    /// In-memory developer audit only. Never serialize this value.
    @ObservationIgnored public private(set) var diagnosticProvisioningForLogAudit: GuestProvisioning?
    #endif
    public let automaticLocalSession: Bool
    public private(set) var isReconnecting = false
    @ObservationIgnored private let artifacts: URL
    @ObservationIgnored private let cloudEgress: Bool
    @ObservationIgnored private let configurationFailure: RuntimeError?
    @ObservationIgnored private let vault: any SessionVault
    @ObservationIgnored private var generation = UUID()
    public var mcpRuntimeEpoch: UUID? {
        controller.guestReady && controller.hasMachine && controller.state == .running ? generation : nil
    }
    public func authorizeMCPClient(name: String, agents: Bool, taskIDs: Set<String>, language: AppLanguage) throws {
        guard let authentication, authentication.phase == .authenticated, mcpRuntimeEpoch != nil else { throw MCPReadError.unauthorized }
        _ = try mcp.authorize(name: name, agents: agents, taskIDs: taskIDs, language: language,
                              session: authentication, runtimeEpoch: { [weak self] in self?.mcpRuntimeEpoch })
    }
    public init(artifacts: URL, paths: ManagedRuntimePaths = .applicationDefault, vault: any SessionVault, cloudEgress: Bool = false, automaticLocalSession: Bool = false, configurationFailure: RuntimeError? = nil) {
        self.configurationFailure = configurationFailure
        self.artifacts = artifacts; self.paths = paths; self.vault = vault; self.cloudEgress = cloudEgress; self.automaticLocalSession = automaticLocalSession
    }
    public func start() async {
        guard !isStarting, controller.mayStart else { return }
        isStarting = true; error = nil; failure = nil; authentication = nil
        let operation = UUID(); generation = operation
        defer { if generation == operation { isStarting = false } }
        do {
            if let configurationFailure { throw configurationFailure }
            await mcp.revokeAll()
            guard generation == operation, !Task.isCancelled else { return }
            try paths.prepareDirectories()
            _ = try PersistentGuestDisk.createIfMissing(at: paths.disk, byteCount: 2 * 1024 * 1024 * 1024)
            let provisioning = try GuestProvisioning.generate(localSession: automaticLocalSession)
            #if DEBUG
            diagnosticProvisioningForLogAudit = provisioning
            #endif
            try await controller.start(artifacts: artifacts, logs: paths.logs, readinessTimeout: .seconds(120), dataDisk: paths.disk, provisioning: provisioning, cloudEgress: cloudEgress)
            for _ in 0..<1300 {
                guard generation == operation, !Task.isCancelled else { return }
                if controller.guestReady || controller.state == .failed || controller.state == .stopped { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard generation == operation else { return }
            guard controller.guestReady else {
                if let runtimeFailure = controller.failure {
                    error = controller.lastError
                    failure = runtimeFailure
                    return
                }
                throw RuntimeError.timeout("NetworkPNTR backend startup")
            }
            if cloudEgress { try controller.enableCloudEgress() }
            let session = AuthenticationSession(client: BackendJSONClient(runtime: controller, provisioning: provisioning), vault: vault, setupToken: provisioning.setupToken,
                                                localCapability: provisioning.localSessionCapability, onInvalidation: { [weak self] in
                guard let self, self.automaticLocalSession, self.generation == operation else { return }
                self.mcp.invalidateAll()
            })
            authentication = session
            await session.refresh()
            if automaticLocalSession, generation == operation { await mcp.revokeAll() }
        } catch {
            if generation == operation { self.error = error.localizedDescription; failure = AppErrorMessage(error, fallback: .runtimeUIUnexpected) }
        }
    }
    public func retryLocalConnection() async {
        guard automaticLocalSession, !isStarting, !isReconnecting else { return }
        if controller.guestReady, let session = authentication {
            let operation = generation
            isReconnecting = true
            defer { isReconnecting = false }
            await mcp.revokeAll()
            guard generation == operation, authentication === session, !Task.isCancelled else { return }
            await session.refresh()
            guard generation == operation, authentication === session else { return }
            await mcp.revokeAll()
        } else if controller.mayStart {
            await start()
        }
    }

    public func stop() async throws {
        generation = UUID(); isStarting = false; authentication = nil
        mcp.invalidateAll()
        async let retired: Void = mcp.revokeAll()
        do { try await controller.stop(); await retired }
        catch { await retired; throw error }
    }
    public func forceStop() async throws {
        generation = UUID(); isStarting = false; authentication = nil
        mcp.invalidateAll()
        async let retired: Void = mcp.revokeAll()
        do { try await controller.forceStop(); await retired }
        catch { await retired; throw error }
    }
}
