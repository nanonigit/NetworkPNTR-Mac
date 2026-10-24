#if DEBUG
import ArtexCore

/// A fresh no-provider UI comparison cannot share any diagnostic seed state.
struct NativeReviewPlan {
    static let seedingFlags: Set<String> = [
        "--attachment-state-diagnostics", "--user-body-review", "--chat-diagnostics",
        "--chat-history-diagnostics", "--dashboard-diagnostics", "--upload-diagnostics",
        "--upload-limit-diagnostics", "--upload-cancellation-diagnostics", "--chat-review", "--mention-review"
    ]
    let noLLM: Bool
    init(arguments: [String]) throws {
        let flags = Set(arguments)
        noLLM = flags.contains("--no-llm-review")
        if noLLM && (!flags.contains("--native-review") || !flags.isDisjoint(with: Self.seedingFlags)) {
            throw RuntimeError.integrity("no-LLM review requires an independent native review fixture")
        }
    }
    @MainActor static func requireNoLLM(client: any BackendJSONTransport) async throws {
        guard try await LLMService(client: client).profiles().isEmpty else {
            throw RuntimeError.integrity("no-LLM review requires zero profiles")
        }
    }
}
#endif
