#if DEBUG
import NetworkPNTRCore
import Foundation

/// Fixed diagnostic scripts execute inside a fresh guest, never on macOS.
@MainActor final class EvidenceFixtureClient {
    struct Body: Codable, Equatable, Sendable { let size: Int64; let sha256: String }
    struct Proof: Decodable {
        let evidenceFixture: Bool
        let uid: Int
        let findingId: Int64
        let bindingIds: [Int64]
        let bodies: [String: Body]
        let counts: [String: Int64]
    }
    static let expectedBodies: [String: Body] = [
        "literal": .init(size: 52, sha256: "e34ddc517f3d74c938352c489e37a79bd855818916bfbce320c03115d6a35224"),
        "binary": .init(size: 5242897, sha256: "732df94bc2b263d03992bc8f8858ab72863d04ced999b95f3552fd2f48270a1d"),
        "empty": .init(size: 0, sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
        "large": .init(size: 135266321, sha256: "97ac5b8e9511e77429ebaf443a3359234751dc8d3fa47b98a5c7abc51ab9d569")]
    private static let zeroKeys = ["foreign_tasks","unsafe_tasks","foreign_explorations","foreign_nodes","foreign_finding_nodes",
        "foreign_findings","foreign_relations","foreign_companies","foreign_assets","foreign_links","foreign_events",
        "profiles","task_profiles","activity","conversations","llm_usage","llm_records","archives","intercepts","retests",
        "notification_channels","notification_deliveries"]
    private static let owned: [String: Int64] = ["traffic_bindings": 2,"traffic_snapshots": 2,"tasks": 11,"explorations": 11,
        "relations": 1,"companies": 1,"assets": 3,"findings": 33,"finding_nodes": 32]
    let sourceSHA256: [String: String]
    private let client: any BackendJSONTransport
    private let encodedSources: String
    private var prepared = false
    init(client: any BackendJSONTransport) throws {
        self.client = client
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var sources: [String: String] = [:], hashes: [String: String] = [:]
        for name in ["findings_seed_guest.py", "findings_fixture_control.py", "evidence_fixture_guest.py"] {
            let data = try Data(contentsOf: root.appendingPathComponent("script/" + name))
            guard data.count <= 24 * 1024, let text = String(data: data, encoding: .utf8) else { throw Self.failure() }
            sources[name] = text; hashes[name] = ArtifactIntegrity.sha256(data)
        }
        let bundle = try JSONEncoder().encode(sources)
        guard bundle.count <= 40 * 1024 else { throw Self.failure() }
        encodedSources = bundle.base64EncodedString(); sourceSHA256 = hashes
    }
    func prepare() async throws -> Proof {
        guard !prepared else { throw Self.failure() }
        prepared = true
        return try await invoke(prepare: true)
    }
    func audit() async throws -> Proof { try await invoke(prepare: false) }
    private func invoke(prepare: Bool) async throws -> Proof {
        try Task.checkCancellation()
        let code = """
        import base64,json,os,sys,types
        os.environ['ARTEX_FINDINGS_FIXTURE']='1'
        bundle=json.loads(base64.b64decode('\(encodedSources)'))
        for name in ['findings_seed_guest','findings_fixture_control','evidence_fixture_guest']:
            module=types.ModuleType(name)
            sys.modules[name]=module
            exec(compile(bundle[name+'.py'],name+'.py','exec'),module.__dict__)
        fixture=sys.modules['evidence_fixture_guest']
        print(json.dumps(fixture.\(prepare ? "prepare" : "audit")()))
        """
        struct Exec: Encodable { let code: String; let timeoutMs = 25_000 }
        struct Request: Encodable { let kind = "script"; let exec: Exec; let params: [String: String] = [:] }
        struct Reply: Decodable { let isError: Bool; let output: String }
        let body = try BackendJSONCoding.encode(Request(exec: Exec(code: code)))
        guard body.count <= 65536 else { throw Self.failure() }
        let response = try await client.send(method: "POST", path: "/api/tools/custom/test", body: body, bearer: nil)
        try Task.checkCancellation()
        guard response.status == 200 else { throw BackendAPIError.status(response.status) }
        guard response.body.count <= 65536 else { throw Self.failure() }
        let reply = try BackendJSONCoding.decode(Reply.self, from: response.body)
        guard !reply.isError, reply.output.utf8.count <= 8192 else { throw Self.failure() }
        let proof = try BackendJSONCoding.decode(Proof.self, from: Data(reply.output.utf8))
        let counts = proof.counts
        guard proof.evidenceFixture, proof.uid == 1000, proof.findingId == 9101, proof.bindingIds == [17001,17002],
              proof.bodies == Self.expectedBodies, Set(counts.keys) == Set(Self.zeroKeys + Array(Self.owned.keys) + ["events"]),
              Self.zeroKeys.allSatisfy({ counts[$0] == 0 }), Self.owned.allSatisfy({ counts[$0.key] == $0.value }),
              let events = counts["events"], (0...3).contains(events) else { throw Self.failure() }
        return proof
    }
    private static func failure() -> RuntimeError { .integrity("evidence fixture guest proof") }
}
#endif
