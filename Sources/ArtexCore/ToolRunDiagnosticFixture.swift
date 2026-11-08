#if DEBUG
import Foundation

/// Fixed synthetic tool history for a reviewed, disposable guest.
@MainActor public enum ToolRunDiagnosticFixture {
    private static let reviewedManifestSHA256 = "9c38d268d350e7ab4e265ca32d686c529d8e09e5facfc2c69581f31589b768d8"

    public struct Reference: Decodable {
        public let sourceCommit: String
        public let sourceSHA256: [String: String]
    }

    private static func sourceRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    public static func seed(client: any BackendJSONTransport, reference: Reference) async throws {
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

    public static func referenceData() throws -> Data {
        let data = try Data(contentsOf: sourceRoot().appendingPathComponent("evidence/tool-runs/pinned-browser-api.json"))
        guard ArtifactIntegrity.sha256(data) == "e49af8c5907995296b9ea1936e114f46fe2962ec157adc18170f6e968c523ad3" else {
            throw RuntimeError.integrity("tool-run fixture reference")
        }
        return data
    }

    public static func verifiedManifest(at directory: URL, reference: Reference) throws -> String {
        let manifest = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        let digest = ArtifactIntegrity.sha256(manifest)
        let metadata = try JSONSerialization.jsonObject(with: manifest) as? [String: Any]
        guard digest == reviewedManifestSHA256, metadata?["sourceCommit"] as? String == reference.sourceCommit else {
            throw RuntimeError.integrity("tool-run VM source")
        }
        return digest
    }
}
#endif
