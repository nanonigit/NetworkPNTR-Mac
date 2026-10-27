#if DEBUG
import ArtexCore
import Foundation

/// Fixed developer sources run only through the isolated guest's authenticated tool test route.
@MainActor final class FindingFixtureClient: FindingFixtureControlling {
    let seedSHA256: String
    let controlSHA256: String
    private let client: any BackendJSONTransport
    private let encodedSources: String
    private var seedStarted = false
    private enum Operation { case seed, audit(Bool) }
    private static let zeroKeys = ["foreign_tasks","unsafe_tasks","foreign_explorations","foreign_nodes","foreign_finding_nodes",
        "foreign_findings","foreign_relations","foreign_companies","foreign_assets","foreign_links","foreign_events",
        "profiles","task_profiles","activity","conversations","llm_usage","llm_records","archives","intercepts","retests",
        "traffic_bindings","traffic_snapshots","notification_channels","notification_deliveries"]
    init(client: any BackendJSONTransport) throws {
        self.client = client
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let seed = try Data(contentsOf:root.appendingPathComponent("script/findings_seed_guest.py"))
        let control = try Data(contentsOf:root.appendingPathComponent("script/findings_fixture_control.py"))
        guard let seedSource = String(data:seed,encoding:.utf8), let controlSource = String(data:control,encoding:.utf8) else { throw Self.failure() }
        let bundle = try JSONEncoder().encode(["seed":seedSource,"control":controlSource])
        guard bundle.count <= 48 * 1024 else { throw Self.failure() }
        encodedSources = bundle.base64EncodedString()
        seedSHA256 = ArtifactIntegrity.sha256(seed); controlSHA256 = ArtifactIntegrity.sha256(control)
    }
    func seed() async throws {
        guard !seedStarted else { throw Self.failure() }; seedStarted = true
        try await audit(fresh:true)
        struct Proof: Decodable { let fixtureSeeded: Bool; let taskIds: [Int64]; let findingIds: [Int64]; let legacyNodeId: Int64; let assetIds: [Int64] }
        let proof = try BackendJSONCoding.decode(Proof.self,from:await invoke(.seed))
        guard proof.fixtureSeeded, proof.taskIds == Array(8101...8111), proof.findingIds == Array(9101...9133),
              proof.legacyNodeId == 15190, proof.assetIds == [8201,8202,8203] else { throw Self.failure() }
        try await audit(fresh:false)
    }
    func verifyNoAgentActivity() async throws { try await audit(fresh:false) }
    private func audit(fresh: Bool) async throws {
        struct Proof: Decodable { let fixtureAudit: Bool; let uid: Int; let fresh: Bool; let counts: [String:Int64] }
        let proof = try BackendJSONCoding.decode(Proof.self,from:await invoke(.audit(fresh)))
        let counts = proof.counts
        let ownedKeys = ["tasks","explorations","relations","companies","assets","findings","finding_nodes","events"]
        guard proof.fixtureAudit, proof.uid == 1000, proof.fresh == fresh,
              Set(counts.keys) == Set(Self.zeroKeys+ownedKeys), counts.values.allSatisfy({$0 >= 0}),
              Self.zeroKeys.allSatisfy({counts[$0] == 0}) else { throw Self.failure() }
        if fresh {
            guard counts.values.allSatisfy({$0 == 0}) else { throw Self.failure() }
        } else {
            let owned = ["tasks","explorations","relations","companies","assets"].compactMap{counts[$0]}
            let dataset = [counts["findings"]!,counts["finding_nodes"]!]
            guard owned == [11,11,1,1,3], [[33,32],[31,31]].contains(dataset), counts["events"]! <= 3 else { throw Self.failure() }
        }
    }
    private func invoke(_ operation: Operation) async throws -> Data {
        try Task.checkCancellation()
        let action: String
        switch operation {
        case .seed: action = "seed.main()"
        case .audit(let fresh): action = "print(json.dumps(control.audit(fresh=\(fresh ? "True" : "False"))))"
        }
        let code = """
        import base64,json,os,sys,types
        os.environ['ARTEX_FINDINGS_FIXTURE']='1'
        bundle=json.loads(base64.b64decode('\(encodedSources)'))
        seed=types.ModuleType('findings_seed_guest')
        exec(compile(bundle['seed'],'findings_seed_guest.py','exec'),seed.__dict__)
        sys.modules['findings_seed_guest']=seed
        control=types.ModuleType('findings_fixture_control')
        exec(compile(bundle['control'],'findings_fixture_control.py','exec'),control.__dict__)
        \(action)
        """
        struct Exec: Encodable { let code: String; let timeoutMs = 20_000 }
        struct Request: Encodable { let kind = "script"; let exec: Exec; let params: [String:String] = [:] }
        struct Reply: Decodable { let isError: Bool; let output: String }
        let response = try await client.send(method:"POST",path:"/api/tools/custom/test",body:BackendJSONCoding.encode(Request(exec:Exec(code:code))),bearer:nil)
        try Task.checkCancellation()
        guard response.status == 200 else { throw BackendAPIError.status(response.status) }
        guard response.body.count <= 64 * 1024 else { throw Self.failure() }
        let reply = try BackendJSONCoding.decode(Reply.self,from:response.body)
        guard !reply.isError, reply.output.utf8.count <= 8192 else { throw Self.failure() }
        return Data(reply.output.utf8)
    }
    private static func failure() -> RuntimeError { .integrity("findings fixture guest proof") }
}
#endif
