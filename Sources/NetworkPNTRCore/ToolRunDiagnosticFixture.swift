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
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("ToolRunFixture"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    public static func seed(client: any BackendJSONTransport, reference: Reference) async throws {
        _ = try await invoke(.seed, client: client, reference: reference)
    }

    public static func setHistoryUnavailable(_ unavailable: Bool, client: any BackendJSONTransport,
                                             reference: Reference) async throws {
        _ = try await invoke(unavailable ? .interrupt : .restore, client: client, reference: reference)
    }

    public static func holdHistoryReads(client: any BackendJSONTransport, reference: Reference) async throws {
        _ = try await invoke(.hold, client: client, reference: reference)
    }

    public static func historyReadWitness(waiting: Bool, client: any BackendJSONTransport, reference: Reference) async throws -> Bool {
        try await invoke(waiting ? .waiting : .locked, client: client, reference: reference)
    }

    private enum Action: String { case seed, interrupt, restore, hold, locked, waiting }

    private static func invoke(_ action: Action, client: any BackendJSONTransport, reference: Reference) async throws -> Bool {
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
        import base64,json,os,subprocess,sys,types
        os.environ['ARTEX_FINDINGS_FIXTURE']='1'
        os.environ['ARTEX_TOOL_RUN_FIXTURE']='1'
        sources=json.loads(base64.b64decode('\(bundle.base64EncodedString())'))
        for name in ['chat_upload_contract_fixture','check_network','findings_seed_guest','tool_run_fixture']:
            module=types.ModuleType(name)
            sys.modules[name]=module
            exec(compile(sources[name],name+'.py','exec'),module.__dict__)
        action='\(action.rawValue)'
        if action == 'seed':
            sys.modules['tool_run_fixture'].seed()
        else:
            network=sys.modules['check_network']
            if not network.is_isolated(network.inspect()):
                raise RuntimeError('tool-run fault requires offline isolation')
            env=sys.modules['findings_seed_guest'].validate_environment()
            psql=['/usr/libexec/postgresql16/psql','-X','--no-password','-qAt','-v','ON_ERROR_STOP=1']
            if action in ('locked','waiting'):
                condition = "granted" if action == 'locked' else "NOT granted"
                sql=f"SELECT EXISTS (SELECT 1 FROM pg_locks WHERE relation = 'public.activity'::regclass AND {condition} AND mode = '{'AccessExclusiveLock' if action == 'locked' else 'AccessShareLock'}');"
                value=subprocess.run(psql,input=sql.encode(),env=env,stdout=subprocess.PIPE,
                                     stderr=subprocess.DEVNULL,timeout=3,check=True).stdout.strip()
                if value not in (b't',b'f'):
                    raise RuntimeError('invalid tool history lock witness')
                print('tool-run-' + action + '-' + value.decode())
                sys.exit(0)
            source,target=('activity','tool_run_fixture_hidden_activity') if action in ('interrupt','hold') else ('tool_run_fixture_hidden_activity','activity')
            sql=f'''BEGIN;
        SET LOCAL lock_timeout = '2s';
        SET LOCAL statement_timeout = '{'24s' if action == 'hold' else '5s'}';
        DO $$
        DECLARE
            fixture_table text := '{source}';
            run_count bigint;
            foreign_rows boolean;
        BEGIN
            IF '{action}' = 'restore' AND to_regclass('public.' || fixture_table) IS NULL THEN
                fixture_table := 'activity';
            END IF;
            EXECUTE format('LOCK TABLE public.%I IN ACCESS EXCLUSIVE MODE', fixture_table);
            EXECUTE format('SELECT count(*) FILTER (WHERE kind = %L), COALESCE(bool_or(tool_use_id IS NULL OR tool_use_id !~ %L),false) FROM public.%I',
                           'tool_use', '^tool-history-fixture-[0-9]+$', fixture_table)
              INTO run_count, foreign_rows;
            IF run_count <> 54 OR foreign_rows THEN
                RAISE EXCEPTION 'tool-run fault requires only the fixed fixture';
            END IF;
            IF '{action}' = 'hold' THEN
                PERFORM pg_sleep(21);
            ELSIF fixture_table <> '{target}' THEN
                EXECUTE format('ALTER TABLE public.%I RENAME TO %I', fixture_table, '{target}');
            END IF;
        END; $$;
        COMMIT;'''
            subprocess.run(psql,
                           input=sql.encode(),env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,
                           timeout=25,check=True)
        print('tool-run-' + action)
        """
        struct Script: Encodable { let code: String; let timeoutMs = 27_000 }
        struct Request: Encodable { let kind = "script"; let exec: Script; let params: [String: String] = [:] }
        struct Reply: Decodable { let output: String; let isError: Bool }
        let response = try await client.send(method: "POST", path: "/api/tools/custom/test",
            body: BackendJSONCoding.encode(Request(exec: Script(code: code))), bearer: nil)
        guard response.status == 200, response.body.count <= 64 * 1024 else {
            throw RuntimeError.integrity("tool-run fixture response")
        }
        let proof = try BackendJSONCoding.decode(Reply.self, from: response.body)
        let witness = proof.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let expected = "tool-run-\(action.rawValue)"
        guard !proof.isError else { throw RuntimeError.integrity("tool-run fixture witness") }
        if action == .locked || action == .waiting {
            if witness == expected + "-t" { return true }
            if witness == expected + "-f" { return false }
        } else if witness == expected {
            return true
        }
        throw RuntimeError.integrity("tool-run fixture witness")
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
