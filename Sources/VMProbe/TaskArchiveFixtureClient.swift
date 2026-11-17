#if DEBUG
import NetworkPNTRCore
import Foundation

/// Developer-only source bundle sent to the isolated guest's existing authenticated tool test route.
@MainActor final class TaskArchiveFixtureClient: TaskArchiveFixtureControlling {
    let seedSHA256: String
    let controlSHA256: String
    private let client: any BackendJSONTransport
    private let encodedSources: String
    private enum Operation { case seed, audit, package(Bool,TaskArchiveFixtureTarget) }
    init(client: any BackendJSONTransport) throws {
        self.client = client
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let seed = try Data(contentsOf:root.appendingPathComponent("script/task_archive_seed_guest.py"))
        let control = try Data(contentsOf:root.appendingPathComponent("script/task_archive_fixture_control.py"))
        guard let seedSource = String(data:seed,encoding:.utf8), let controlSource = String(data:control,encoding:.utf8) else { throw Self.failure() }
        let bundle = try JSONEncoder().encode(["seed":seedSource,"control":controlSource])
        guard bundle.count <= 48 * 1024 else { throw Self.failure() }
        encodedSources = bundle.base64EncodedString()
        seedSHA256 = ArtifactIntegrity.sha256(seed); controlSHA256 = ArtifactIntegrity.sha256(control)
    }
    func seed() async throws {
        struct Proof: Decodable { let fixtureSeeded: Bool; let terminalTaskIds: [Int64]; let files: [TaskArchiveFileProof] }
        let proof = try BackendJSONCoding.decode(Proof.self,from:await invoke(.seed))
        guard proof.fixtureSeeded, proof.terminalTaskIds == [7101,7102], proof.files.count == TaskArchiveExercise.files.count,
              zip(proof.files,TaskArchiveExercise.files).allSatisfy({ p,f in p.path.utf8.elementsEqual(f.path.utf8) && p.size == Int64(f.data.count) && p.sha256 == ArtifactIntegrity.sha256(f.data) }) else { throw Self.failure() }
    }
    func verifyNoAgentActivity() async throws {
        struct Counts: Decodable {
            let foreignTasks: Int64, foreignArchives: Int64, profiles: Int64, activity: Int64, conversations: Int64, llmUsage: Int64, llmRecords: Int64
            var empty: Bool { [foreignTasks,foreignArchives,profiles,activity,conversations,llmUsage,llmRecords].allSatisfy{$0 == 0} }
        }
        struct Proof: Decodable { let fixtureAudit: Bool; let uid: Int; let counts: Counts }
        let proof = try BackendJSONCoding.decode(Proof.self,from:await invoke(.audit))
        guard proof.fixtureAudit, proof.uid == 1000, proof.counts.empty else { throw Self.failure() }
    }
    func setPackageHidden(_ hidden: Bool, target: TaskArchiveFixtureTarget) async throws {
        guard target.archiveID > 0, target.sha256.utf8.count == 64, target.sha256.utf8.allSatisfy({(48...57).contains($0) || (97...102).contains($0)}) else { throw Self.failure() }
        struct Proof: Decodable { let fixtureControl: Bool; let operation: String; let archiveId: Int64; let taskId: Int64; let sha256: String; let uid: Int }
        let proof = try BackendJSONCoding.decode(Proof.self,from:await invoke(.package(hidden,target)))
        guard proof.fixtureControl, proof.operation == (hidden ? "hide" : "repair"), proof.archiveId == target.archiveID,
              proof.taskId == 7101, proof.sha256 == target.sha256, proof.uid == 1000 else { throw Self.failure() }
    }
    private func invoke(_ operation: Operation) async throws -> Data {
        try Task.checkCancellation()
        let action: String
        switch operation {
        case .seed: action = "seed.main()"
        case .audit: action = "print(json.dumps(control.audit()))"
        case let .package(hidden,target): action = "print(json.dumps(control.set_package_hidden(\(hidden ? "True" : "False"),\(target.archiveID),'\(target.sha256)')))"
        }
        let code = """
        import base64,json,os,sys,types
        os.environ['ARTEX_ARCHIVE_FIXTURE']='1'
        bundle=json.loads(base64.b64decode('\(encodedSources)'))
        seed=types.ModuleType('task_archive_seed_guest')
        exec(compile(bundle['seed'],'task_archive_seed_guest.py','exec'),seed.__dict__)
        sys.modules['task_archive_seed_guest']=seed
        control=types.ModuleType('task_archive_fixture_control')
        exec(compile(bundle['control'],'task_archive_fixture_control.py','exec'),control.__dict__)
        \(action)
        """
        struct Exec: Encodable { let code: String; let timeoutMs = 20_000 }
        struct Request: Encodable { let kind = "script"; let exec: Exec; let params: [String:String] = [:] }
        struct ToolReply: Decodable { let isError: Bool; let output: String }
        let response = try await client.send(method:"POST",path:"/api/tools/custom/test",body:BackendJSONCoding.encode(Request(exec:Exec(code:code))),bearer:nil)
        try Task.checkCancellation()
        guard response.status == 200 else { throw BackendAPIError.status(response.status) }
        guard response.body.count <= 64 * 1024 else { throw Self.failure() }
        let reply = try BackendJSONCoding.decode(ToolReply.self,from:response.body)
        guard !reply.isError, reply.output.utf8.count <= 8192 else { throw Self.failure() }
        return Data(reply.output.utf8)
    }
    private static func failure() -> RuntimeError { .integrity("archive fixture guest proof") }
}
#endif
