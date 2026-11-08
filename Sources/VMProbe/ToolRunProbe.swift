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
    private static let reviewedManifestSHA256 = "9c38d268d350e7ab4e265ca32d686c529d8e09e5facfc2c69581f31589b768d8"

    private final class Vault: SessionVault {
        var token: String?
        func load() throws -> String? { token }
        func save(_ token: String) throws { self.token = token }
        func remove() throws { token = nil }
    }

    private struct Reference: Decodable {
        let sourceCommit: String
        let sourceSHA256: [String: String]
    }

    private static func sourceRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private static func seed(client: AuthenticatedBackendClient, reference: Reference) async throws {
        let modules = ["chat_upload_contract_fixture", "check_network", "findings_seed_guest", "tool_run_fixture"]
        var sources: [String: String] = [:]
        for name in modules {
            let file = name + ".py"
            let data = try Data(contentsOf: sourceRoot().appendingPathComponent(name == "check_network" ? "guest/" + file : "script/" + file))
            guard ArtifactIntegrity.sha256(data) == reference.sourceSHA256[file],
                  let source = String(data: data, encoding: .utf8) else {
                throw RuntimeError.integrity("tool-run source mismatch")
            }
            sources[name] = source
        }
        let bundle = try JSONEncoder().encode(sources)
        guard bundle.count <= 48 * 1024 else { throw RuntimeError.integrity("tool-run source size") }
        let code = """
        import base64,json,os,sys,types
        os.environ['ARTEX_FINDINGS_FIXTURE']='1'
        os.environ['ARTEX_TOOL_RUN_FIXTURE']='1'
        sources=json.loads(base64.b64decode('\(bundle.base64EncodedString())'))
        for name in ['chat_upload_contract_fixture','check_network','findings_seed_guest','tool_run_fixture']:
            module=types.ModuleType(name)
            sys.modules[name]=module
            exec(compile(sources[name],name+'.py','exec'),module.__dict__)
        sys.modules['tool_run_fixture'].seed()
        print('tool-run-seeded')
        """
        struct Script: Encodable { let code: String; let timeoutMs = 20_000 }
        struct Request: Encodable { let kind = "script"; let exec: Script; let params: [String: String] = [:] }
        struct Reply: Decodable { let output: String; let isError: Bool }
        let response = try await client.send(method: "POST", path: "/api/tools/custom/test",
            body: BackendJSONCoding.encode(Request(exec: Script(code: code))), bearer: nil)
        guard response.status == 200, response.body.count <= 64 * 1024 else {
            throw RuntimeError.integrity("tool-run seed response")
        }
        let proof = try BackendJSONCoding.decode(Reply.self, from: response.body)
        guard !proof.isError, proof.output.trimmingCharacters(in: .whitespacesAndNewlines) == "tool-run-seeded" else {
            throw RuntimeError.integrity("tool-run seed witness")
        }
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
            let referenceData = try Data(contentsOf: sourceRoot().appendingPathComponent("evidence/tool-runs/pinned-browser-api.json"))
            let reference = try JSONDecoder().decode(Reference.self, from: referenceData)
            let manifest = try Data(contentsOf: artifacts.appendingPathComponent("manifest.json"))
            let manifestSHA256 = ArtifactIntegrity.sha256(manifest)
            let metadata = try JSONSerialization.jsonObject(with: manifest) as? [String: Any]
            guard manifestSHA256 == reviewedManifestSHA256,
                  metadata?["sourceCommit"] as? String == reference.sourceCommit else {
                throw RuntimeError.integrity("tool-run VM source")
            }
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
            try await seed(client: client, reference: reference)
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
