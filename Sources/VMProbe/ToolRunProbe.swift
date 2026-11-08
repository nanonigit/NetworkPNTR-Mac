import ArtexCore
import Darwin
import Foundation

@MainActor enum ToolRunProbe {
    static func run(_ args: [String]) async {
        #if DEBUG
        guard args.count == 2 else {
            print("Usage: VMProbe --tool-runs ARTIFACTS NEW_PRIVATE_OUTPUT")
            exit(2)
        }
        await exercise(artifacts: URL(fileURLWithPath: args[0]), output: URL(fileURLWithPath: args[1]))
        #else
        print("Tool run probe requires a developer build")
        exit(2)
        #endif
    }

    #if DEBUG
    private final class Vault: SessionVault {
        var token: String?
        func load() throws -> String? { token }
        func save(_ token: String) throws { self.token = token }
        func remove() throws { token = nil }
    }

    private static func snapshots(service: ToolRunService) async throws -> [String: [Any]] {
        let keyword = "日本語+ O'Neil"
        let cases: [(String, ToolRunFilter)] = [
            ("all", .init()), ("exploration", .init(explorationID: 8801)),
            ("keyword", .init(keyword: keyword)), ("combined", .init(explorationID: 8802, keyword: keyword)),
            ("tool", .init(keyword: "WebFetch")), ("empty", .init(explorationID: 9999))
        ]
        var snapshots: [String: [Any]] = [:]
        for (name, filter) in cases {
            var pages: [[String: Any]] = []
            for (page, size): (Int64, Int) in [(0, 25), (1, 25), (2, 25), (0, 50), (0, 100)] {
                let result = try await service.list(filter: filter, page: page, size: size)
                let rows: [[String: Any]] = result.commands.map {
                    ["id": $0.id, "exploration_id": $0.explorationId, "worker": $0.worker, "tool": $0.tool,
                     "command": $0.command, "output": $0.output, "is_error": $0.isError, "created_at": $0.createdAt]
                }
                pages.append(["commands": rows, "total": result.total])
            }
            let stats = try await service.stats(filter: filter).map {
                ["tool": $0.tool, "total": $0.total, "errors": $0.errors] as [String: Any]
            }
            snapshots[name] = [pages, ["stats": stats]]
        }
        return snapshots
    }

    private static func exercise(artifacts: URL, output: URL) async {
        let controller = VMController()
        var stage = "prepare"
        do {
            guard output.path.withCString({ Darwin.mkdir($0, 0o700) }) == 0 else {
                throw RuntimeError.integrity("tool-run private output")
            }
            let referenceData = try ToolRunDiagnosticFixture.referenceData()
            let reference = try JSONDecoder().decode(ToolRunDiagnosticFixture.Reference.self, from: referenceData)
            let manifestSHA256 = try ToolRunDiagnosticFixture.verifiedManifest(at: artifacts, reference: reference)
            let disk = output.appendingPathComponent("state.ext4")
            let logs = output.appendingPathComponent("boot")
            _ = try PersistentGuestDisk.createIfMissing(at: disk, byteCount: 2 * 1024 * 1024 * 1024)
            let provisioning = try GuestProvisioning.generate()
            stage = "boot"
            try await controller.start(artifacts: artifacts, logs: logs, readinessTimeout: .seconds(120),
                                       dataDisk: disk, provisioning: provisioning)
            for _ in 0..<1200 {
                if controller.guestReady || controller.state == .failed || controller.state == .stopped { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard controller.guestReady, !controller.cloudEgressActive else { throw RuntimeError.integrity("tool-run VM readiness") }
            stage = "authentication"
            let raw = BackendJSONClient(runtime: controller, provisioning: provisioning)
            for path in ["/api/commands", "/api/commands/stats"] {
                guard try await raw.send(method: "GET", path: path, body: nil, bearer: nil).status == 401 else {
                    throw RuntimeError.integrity("tool-run protected API")
                }
            }
            let vault = Vault()
            let session = AuthenticationSession(client: raw, vault: vault, setupToken: provisioning.setupToken)
            let password = UUID().uuidString + "-tool-run"
            await session.refresh()
            guard session.phase == .needsSetup else { throw RuntimeError.integrity("tool-run fresh account") }
            await session.setup(password: password, confirmation: password)
            guard session.phase == .authenticated, let token = vault.token else { throw RuntimeError.integrity("tool-run login") }
            let client = AuthenticatedBackendClient(session: session)
            let service = ToolRunService(client: client)
            let empty = try await service.list()
            guard empty.total == 0, empty.commands.isEmpty, try await service.stats().isEmpty else {
                throw RuntimeError.integrity("tool-run fresh history")
            }
            stage = "seed"
            try await ToolRunDiagnosticFixture.seed(client: client, reference: reference)
            stage = "snapshots"
            let observed = try await snapshots(service: service)
            stage = "shutdown"
            session.logout()
            try await controller.stop()
            let audit = GuestBootDiagnostics.audit(logDirectory: logs, tokens: [token, password, provisioning.transportToken, provisioning.setupToken])
            guard !controller.hasMachine, audit.complete, audit.isolationWitnessesPresent, audit.credentialsAbsent,
                  audit.diagnostics.isEmpty, audit.formatStageObserved else {
                throw RuntimeError.integrity("tool-run stopped audit")
            }
            let result: [String: Any] = [
                "sourceCommit": reference.sourceCommit, "referenceSHA256": ArtifactIntegrity.sha256(referenceData),
                "guestManifestSHA256": manifestSHA256,
                "protectedStatuses": [401, 401], "freshEmpty": true, "cooperativeStop": true,
                "isolated": true, "snapshots": observed
            ]
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output.appendingPathComponent("tool-runs-vm.json"), options: .atomic)
            print("PASS tool_run_native_reads=36 isolated=true stopped=true")
        } catch {
            if controller.hasMachine { try? await controller.forceStop() }
            print("FAIL tool_run_stage=\(stage) stopped=\(!controller.hasMachine)")
            exit(1)
        }
    }
    #endif
}
