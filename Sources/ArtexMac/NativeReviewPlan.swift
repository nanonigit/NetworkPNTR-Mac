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
    let skillVisibility: Bool
    let toolRuns: Bool
    let toolRunFailure: Bool
    let toolRunCancellation: Bool
    init(arguments: [String]) throws {
        let flags = Set(arguments)
        toolRuns = flags.contains("--tool-runs-review")
        toolRunFailure = flags.contains("--tool-runs-failure-review")
        toolRunCancellation = flags.contains("--tool-runs-cancellation-review")
        if ((toolRunFailure || toolRunCancellation) && !toolRuns) || (toolRunFailure && toolRunCancellation) {
            throw RuntimeError.integrity("tool-run failure and cancellation require separate review fixtures")
        }
        skillVisibility = flags.contains("--skill-visibility-diagnostics")
        let explicitNoLLM = flags.contains("--no-llm-review")
        if skillVisibility && (explicitNoLLM || flags.contains("--native-review") || !flags.isDisjoint(with: Self.seedingFlags)) {
            throw RuntimeError.integrity("skill visibility requires an independent diagnostic fixture")
        }
        if toolRuns && (!explicitNoLLM || skillVisibility) {
            throw RuntimeError.integrity("tool-run review requires an independent no-LLM fixture")
        }
        noLLM = explicitNoLLM || skillVisibility
        if explicitNoLLM && (!flags.contains("--native-review") || !flags.isDisjoint(with: Self.seedingFlags)) {
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
