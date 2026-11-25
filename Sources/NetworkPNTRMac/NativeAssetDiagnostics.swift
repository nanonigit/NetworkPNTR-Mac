#if DEBUG
import Foundation
import NetworkPNTRCore

/// Loads synthetic rows for the Assets UI without tasks, models or external requests.
@MainActor enum NativeAssetDiagnostics {
    static func seed(session: AuthenticationSession, directory: URL) async throws {
        guard NativeMCPTaskDiagnostics.owns(directory: directory, requested: RuntimeFactory.diagnosticsDirectory) else {
            throw RuntimeError.integrity("owned asset diagnostic directory")
        }
        let client = AuthenticatedBackendClient(session: session)
        let assets = AssetCatalogService(client: client)
        try await NativeReviewPlan.requireNoLLM(client: client)
        guard try await assets.counts().values.allSatisfy({ $0 == 0 }) else {
            throw RuntimeError.integrity("fresh asset inventory")
        }
        guard let fixture = Bundle.main.url(forResource: "asset_catalog_seed_guest", withExtension: "py",
                                            subdirectory: "Diagnostics") else {
            throw RuntimeError.integrity("asset fixture resource")
        }
        let data = try Data(contentsOf: fixture)
        guard ArtifactIntegrity.sha256(data) == "1a665388abc7f11e43c7ba315d8660cc966ebfc6bb57b1ec5ed1a4ff35af7659",
              let source = String(data: data, encoding: .utf8) else {
            throw RuntimeError.integrity("asset fixture resource digest")
        }
        let code = "import os\nos.environ['NETWORKPNTR_ASSET_FIXTURE'] = '1'\n" + source
        let request = try JSONSerialization.data(withJSONObject: [
            "kind": "script", "exec": ["code": code, "timeout_ms": 20_000], "params": [:]
        ])
        let reply = try await session.authenticatedRequest(method: "POST", path: "/api/tools/custom/test", body: request)
        guard reply.status == 200, let result = try JSONSerialization.jsonObject(with: reply.body) as? [String: Any],
              result["is_error"] as? Bool == false, let output = result["output"] as? String,
              output.utf8.count <= 1024,
              let proof = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any],
              proof["asset_fixture_seeded"] as? Bool == true, proof["linux_guest"] as? Bool == true,
              proof["uid"] as? Int == 1000, proof["asset_count"] as? Int == 26 else {
            throw RuntimeError.integrity("asset seed receipt")
        }
        let page = try await assets.list(type: .rootDomain)
        guard page.total == 26, page.assets.count == 26,
              Set(page.assets.compactMap(\.domain)) == Set((1...26).map { "fixture-\($0).example.test" }) else {
            throw RuntimeError.integrity("asset fixture readback")
        }
        try await NativeReviewPlan.requireNoLLM(client: client)
    }
}
#endif
