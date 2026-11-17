#if DEBUG
import NetworkPNTRCore
import Foundation

/// Fixed diagnostic scripts execute inside a fresh guest, never on macOS.
@MainActor final class CapturedFixtureClient {
    struct Proof: Decodable {
        let capturedNativeFixture: Bool
        let uid, findingId, records: Int
        let manifestSha256: String
        let counts: [String: Int64]
        let sourceSha256: [String: String]
    }
    static let manifestSHA256 = "cbbff8fe682f4261362db3b741abeff9b429aa622c59ba4042663e512fe375ba"
    private static let zeroKeys = ["foreign_tasks","unsafe_tasks","foreign_explorations","foreign_nodes","foreign_finding_nodes",
        "foreign_findings","foreign_relations","foreign_companies","foreign_assets","foreign_links","foreign_events",
        "profiles","task_profiles","activity","conversations","llm_usage","llm_records","archives","intercepts","retests",
        "notification_channels","notification_deliveries"]
    private static let owned: [String: Int64] = ["tasks": 11,"explorations": 11,
        "relations": 1,"companies": 1,"assets": 3,"findings": 33,"finding_nodes": 32]
    let sourceSHA256: [String: String]
    private let client: any BackendJSONTransport
    private let encodedSources: String
    private var prepared = false
    init(client: any BackendJSONTransport) throws {
        self.client = client
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var sources: [String: String] = [:], hashes: [String: String] = [:]
        for name in ["findings_seed_guest.py", "findings_fixture_control.py", "check_network.py", "captured_fixture_guest.py", "captured_native_guest.py"] {
            let data = try Data(contentsOf: root.appendingPathComponent((name == "check_network.py" ? "guest/" : "script/") + name))
            guard data.count <= 24 * 1024, let text = String(data: data, encoding: .utf8) else { throw Self.failure() }
            sources[name] = text; hashes[name] = ArtifactIntegrity.sha256(data)
        }
        let bundle = try JSONEncoder().encode(sources)
        guard bundle.count <= 44 * 1024 else { throw Self.failure() }
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
        import base64,hashlib,json,os,sys,types
        os.environ['ARTEX_FINDINGS_FIXTURE']='1'
        os.environ['ARTEX_CAPTURE_FIXTURE']='1'
        bundle=json.loads(base64.b64decode('\(encodedSources)'))
        for name in ['findings_seed_guest','findings_fixture_control','check_network','captured_fixture_guest','captured_native_guest']:
            module=types.ModuleType(name)
            sys.modules[name]=module
            exec(compile(bundle[name+'.py'],name+'.py','exec'),module.__dict__)
        fixture=sys.modules['captured_native_guest']
        result=fixture.\(prepare ? "prepare" : "audit")()
        result['source_sha256']={name:hashlib.sha256(text.encode()).hexdigest() for name,text in bundle.items()}
        print(json.dumps(result))
        """
        struct Exec: Encodable { let code: String; let timeoutMs = 75_000 }
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
        guard proof.capturedNativeFixture, proof.uid == 1000, proof.findingId == 9101, proof.records == 29,
              proof.manifestSha256 == Self.manifestSHA256, proof.sourceSha256 == sourceSHA256,
              Set(counts.keys) == Set(Self.zeroKeys + Array(Self.owned.keys) + ["events","traffic_bindings","traffic_snapshots"]),
              Self.zeroKeys.allSatisfy({ counts[$0] == 0 }), Self.owned.allSatisfy({ counts[$0.key] == $0.value }),
              counts["events"] == 0, counts["traffic_bindings"] == (prepare ? 0 : 1), counts["traffic_snapshots"] == (prepare ? 0 : 2) else { throw Self.failure() }
        return proof
    }
    private static func failure() -> RuntimeError { .integrity("captured fixture guest proof") }
}
#endif
