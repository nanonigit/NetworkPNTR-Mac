import NetworkPNTRCore
import Darwin
import Foundation

@MainActor enum CloudLiveModelsProbe {
    static func run(_ args: [String]) async {
        #if DEBUG
        let localSession = args.count == 3 && args[2] == "--local-session"
        if args.count == 2 || localSession {
            await exercise(artifacts: URL(fileURLWithPath: args[0]), output: URL(fileURLWithPath: args[1]), localSession: localSession)
            return
        }
        #endif
        FileHandle.standardError.write(Data("Usage: DEBUG VMProbe --cloud-live-models ARTIFACTS NEW_PRIVATE_OUTPUT [--local-session]\n".utf8))
        exit(2)
    }

    #if DEBUG
    private static let invalidKey = "artx-diagnostic-intentionally-invalid"

    private final class Vault: SessionVault {
        var token: String?
        func load() throws -> String? { token }
        func save(_ token: String) throws { self.token = token }
        func remove() throws { token = nil }
    }

    private struct Result: Encodable {
        let provider: String
        let downstreamStatus: Int?
        let backendFailureKind: String?
        let upstreamStatus: Int?
        let authenticationRejected: Bool
        let appRejected: Bool
    }

    private final class ObservedModelRequest: BackendJSONTransport {
        private let authenticated: AuthenticatedBackendClient
        private let provider: LLMCloudProvider
        private(set) var dispatched = false
        private(set) var downstreamStatus: Int?
        private(set) var backendFailureKind: String?
        private(set) var upstreamStatus: Int?
        private(set) var authenticationRejected = false

        init(session: AuthenticationSession, provider: LLMCloudProvider) {
            authenticated = AuthenticatedBackendClient(session: session)
            self.provider = provider
        }

        func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
            guard !dispatched, method == "POST", path == "/api/llm/models", bearer == nil else {
                throw RuntimeError.integrity("live models operation")
            }
            dispatched = true
            let response = try await authenticated.send(method: method, path: path, body: body, bearer: bearer)
            downstreamStatus = response.status
            if response.status == 200,
               let payload = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
               payload["ok"] as? Bool == false, let error = payload["error"] as? String {
                backendFailureKind = CloudLiveModelsProbe.classifyBackendFailure(error)
                // The pinned backend adds this prefix only after receiving and reading the upstream response.
                let parts = error.split(separator: " ", maxSplits: 5)
                if parts.count == 6, parts[0] == "API", parts[1] == "가", parts[3] == "를",
                   parts[4] == "반환했습니다:", let status = Int(parts[2]), (400...599).contains(status) {
                    upstreamStatus = status
                    authenticationRejected = status == 401 ||
                        (provider == .gemini && [400, 403].contains(status) && Self.rejectsGeminiKey(parts[5]))
                }
            }
            return response
        }

        private static func rejectsGeminiKey(_ detail: Substring) -> Bool {
            if detail.contains("API_KEY_INVALID") || detail.contains("API key not valid") { return true }
            guard let body = try? JSONSerialization.jsonObject(with: Data(detail.utf8)) as? [String: Any],
                  let error = body["error"] as? [String: Any], error["status"] as? String == "INVALID_ARGUMENT",
                  let message = error["message"] as? String else { return false }
            return message.lowercased().hasPrefix("api key ")
        }
    }

    nonisolated static func classifyBackendFailure(_ message: String) -> String {
        let text = message.lowercased()
        let fixed: [(String, String)] = [
            ("cloud egress target is not permitted", "target-policy"),
            ("cloud egress configuration is not supported", "vsock-configuration"),
            ("invalid cloud egress response", "vsock-response"),
            ("network is unreachable", "network-unreachable"),
            ("connection refused", "connection-refused"),
            ("permission denied", "permission-denied"),
            ("context deadline exceeded", "deadline"), ("timeout", "timeout"),
            ("no such host", "dns"), ("certificate", "tls-certificate"),
            ("unexpected eof", "unexpected-eof"), ("eof", "eof"),
            ("api key 가 제공되지 않았습니다", "missing-test-key")
        ]
        return fixed.first(where: { text.contains($0.0) })?.1 ?? "unclassified"
    }

    private static func exercise(artifacts: URL, output: URL, localSession: Bool) async {
        let vault = Vault()
        let paths = ManagedRuntimePaths(root: output.appendingPathComponent("State"))
        let runtime = DesktopRuntime(artifacts: artifacts, paths: paths, vault: vault, cloudEgress: true, automaticLocalSession: localSession)
        var stage = "prepare"
        do {
            guard mkdir(output.path, 0o700) == 0 else { throw RuntimeError.integrity("new private output required") }
            if localSession {
                let manifestData = try Data(contentsOf: artifacts.appendingPathComponent("manifest.json"))
                guard ArtifactIntegrity.sha256(manifestData) == GuestArtifacts.nativeSessionCloudCompositeManifestSHA256 else {
                    throw RuntimeError.integrity("reviewed native-session cloud manifest")
                }
            }
            stage = "boot"
            await runtime.start()
            guard runtime.error == nil, runtime.controller.cloudEgressActive,
                  let session = runtime.authentication, session.phase == (localSession ? .authenticated : .needsSetup) else {
                throw RuntimeError.integrity("live models boot")
            }
            stage = "auth"
            let password = UUID().uuidString + "-live-models"
            if !localSession { await session.setup(password: password, confirmation: password) }
            guard session.phase == .authenticated, let token = localSession ? session.diagnosticBearerForLogAudit : vault.token else {
                throw RuntimeError.integrity("live models session")
            }
            if localSession {
                guard let provisioning = runtime.diagnosticProvisioningForLogAudit else { throw RuntimeError.integrity("native cloud provisioning") }
                let response = try await BackendJSONClient(runtime: runtime.controller, provisioning: provisioning)
                    .send(method: "GET", path: "/api/health", body: nil, bearer: nil)
                guard response.status == 200,
                      let health = try JSONSerialization.jsonObject(with: response.body) as? [String: Any],
                      health["ok"] as? Bool == true, health["version"] as? String == "dev" else {
                    throw RuntimeError.integrity("native cloud composite backend version")
                }
            }
            let readClient = AuthenticatedBackendClient(session: session)
            let readLLM = LLMService(client: readClient)
            let chat = ChatService(client: readClient)
            var results: [Result] = []
            for provider in LLMCloudProvider.allCases {
                stage = "models-\(provider.rawValue)"
                let observer = ObservedModelRequest(session: session, provider: provider)
                var draft = LLMProfileDraft(provider: provider)
                draft.apiKey = invalidKey
                var appRejected = false
                do {
                    _ = try await LLMService(client: observer).models(draft)
                } catch BackendAPIError.validation(.modelList) {
                    appRejected = true
                } catch {
                    // Continue independent probes. A missing status records an unverified exchange.
                }
                guard observer.dispatched else { throw RuntimeError.integrity("live models was not dispatched") }
                results.append(Result(provider: provider.rawValue, downstreamStatus: observer.downstreamStatus, backendFailureKind: observer.backendFailureKind, upstreamStatus: observer.upstreamStatus,
                                      authenticationRejected: observer.authenticationRejected, appRejected: appRejected))
                print("cloud_live_models provider=\(provider.rawValue) status=\(observer.upstreamStatus.map(String.init) ?? "unconfirmed") auth_rejected=\(observer.authenticationRejected)")
            }
            stage = "stop"
            guard try await readLLM.profiles().isEmpty, try await chat.conversations().isEmpty else {
                throw RuntimeError.integrity("live models wrote a profile or conversation")
            }
            try await runtime.stop()
            guard let provisioning = runtime.diagnosticProvisioningForLogAudit else { throw RuntimeError.integrity("live models provisioning audit") }
            var secrets = [token, password, invalidKey, provisioning.transportToken, provisioning.setupToken]
            if let capability = provisioning.localSessionCapability { secrets.append(capability) }
            let audit = GuestBootDiagnostics.audit(logDirectory: paths.logs, tokens: secrets)
            guard !runtime.controller.hasMachine, !runtime.controller.cloudEgressActive,
                  audit.complete, audit.isolationWitnessesPresent, audit.credentialsAbsent,
                  audit.diagnostics.isEmpty, audit.formatStageObserved else {
                throw RuntimeError.integrity("live models stopped audit")
            }
            stage = "results"
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(results).write(to: output.appendingPathComponent("cloud-live-models.json"), options: .atomic)
            guard results.allSatisfy({ $0.authenticationRejected && $0.appRejected }) else { exit(1) }
            print("PASS cloud_live_models=4 nic=0 shares=0 stopped=true")
        } catch {
            if runtime.controller.hasMachine { try? await runtime.forceStop() }
            FileHandle.standardError.write(Data("FAIL cloud_live_models_stage=\(stage)\n".utf8))
            exit(1)
        }
    }
    #endif
}
