#if DEBUG
import AppKit
import Darwin
import NetworkPNTRCore
import Foundation

/// Exercises this app's production services with an isolated fixture disk and Keychain item.
/// Internal rendering/service diagnostics do not replace external native click acceptance.
@MainActor enum NativeDiagnostics {
    static func run(environment: DesktopRuntime, directory: URL) async {
        let toolRunReview = CommandLine.arguments.contains("--tool-runs-review")
        let assetReview = CommandLine.arguments.contains("--asset-catalog-review")
        let freshDirectory = toolRunReview || assetReview || CommandLine.arguments.contains("--log-history-review")
        if freshDirectory, directory.path.withCString({ Darwin.mkdir($0, 0o700) }) != 0 {
            FileHandle.standardError.write(Data("This review requires a new private directory\n".utf8))
            NSApp.terminate(nil)
            return
        }
        var result: [String: Any] = ["ui_click_workflow_verified": false, "visual_acceptance": "pending external native automation"]
        var userBodyIDs: [Int64] = []
        var faultToRestore: ToolRunDiagnosticFixture.Reference?
        do {
            let plan = try NativeReviewPlan(arguments: CommandLine.arguments)
            if !freshDirectory {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            let toolRunReference: ToolRunDiagnosticFixture.Reference?
            if plan.toolRuns {
                let reference = try JSONDecoder().decode(ToolRunDiagnosticFixture.Reference.self, from: ToolRunDiagnosticFixture.referenceData())
                let guest = Bundle.main.resourceURL!.appendingPathComponent("Guest")
                result["tool_run_guest_manifest_sha256"] = try ToolRunDiagnosticFixture.verifiedManifest(at: guest, reference: reference)
                toolRunReference = reference
            } else {
                toolRunReference = nil
            }
            result["native_window_rendered"] = try capture(to: directory.appendingPathComponent("native-launch.png"))
            await environment.start()
            for _ in 0..<1500 {
                if (!environment.isStarting && environment.authentication?.phase != nil && environment.authentication?.phase != .checking) || environment.error != nil || environment.controller.state == .failed { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard let authentication = environment.authentication, authentication.phase == .needsSetup else { throw RuntimeError.integrity(environment.authentication?.error ?? environment.error ?? environment.controller.lastError ?? "fresh native setup state") }
            result["app_owned_backend_ready"] = environment.controller.guestReady
            result["virtual_cpu_count"] = environment.controller.configuredCPUCount
            try await Task.sleep(for: .milliseconds(300))
            result["setup_content_snapshot"] = try capture(to: directory.appendingPathComponent("native-setup.png"))
            let password = UUID().uuidString + "-native-fixture"
            await authentication.setup(password: "short", confirmation: "short")
            guard authentication.phase == .needsSetup, authentication.error != nil else { throw RuntimeError.integrity("native setup validation") }
            try await Task.sleep(for: .milliseconds(300))
            result["validation_content_snapshot"] = try capture(to: directory.appendingPathComponent("native-validation.png"))
            await authentication.setup(password: password, confirmation: password)
            guard authentication.phase == .authenticated else { throw RuntimeError.integrity(authentication.error ?? "native setup authentication") }
            result["native_setup_authenticated"] = true
            if CommandLine.arguments.contains("--attachment-state-diagnostics") {
                try await NativeAttachmentHandoffDiagnostics.run(session:authentication,directory:directory)
                result["native_attachment_handoff_recovery_and_file_preservation"] = true
            }
            let llm: NativeLLMDiagnostics.Snapshot?
            if plan.noLLM {
                try await NativeReviewPlan.requireNoLLM(client: AuthenticatedBackendClient(session: authentication))
                llm = nil
                result["native_review_has_no_llm_profiles"] = true
            } else {
                llm = try await NativeLLMDiagnostics.run(session: authentication, directory: directory)
                result["native_llm_three_formats_crud_key_preservation_pool_retry"] = true
            }
            if CommandLine.arguments.contains("--user-body-review") {
                userBodyIDs = try await NativeUserBodyDiagnostics.seed(client: AuthenticatedBackendClient(session: authentication), directory: directory)
                result["native_persisted_user_body_fixture"] = true
            } else { userBodyIDs = [] }
            if CommandLine.arguments.contains("--chat-diagnostics") {
                try await NativeChatDiagnostics.run(session: authentication, directory: directory)
                result["native_chat_finite_crud"] = true
            }
            if CommandLine.arguments.contains("--chat-history-diagnostics") {
                let history = try await NativeChatHistoryDiagnostics.run(session: authentication, directory: directory)
                try await environment.stop()
                await environment.start()
                guard let restored = environment.authentication, restored.phase == .authenticated else {
                    throw RuntimeError.integrity("chat history restart authentication")
                }
                try await NativeChatHistoryDiagnostics.verifyPersistence(history, session: restored, directory: directory)
                result["native_chat_populated_history_and_final_delta"] = true
                result["native_chat_history_restart_persistence"] = true
            }
            if CommandLine.arguments.contains("--dashboard-diagnostics") {
                guard let current = environment.authentication, current.phase == .authenticated else { throw RuntimeError.integrity("dashboard seed authentication") }
                try await NativeDashboardDiagnostics.seed(session: current, directory: directory)
            }
            if plan.skillVisibility {
                try await verifySkillFixture(session: authentication, expectedVisible: true, remove: true)
                result["native_seeded_skill_removed"] = true
            }
            if plan.logHistoryReview {
                try await NativeLogHistoryDiagnostics.seed(session: authentication, directory: directory)
            }
            try await environment.stop()
            await environment.start()
            guard environment.authentication?.phase == .authenticated else { throw RuntimeError.integrity(environment.authentication?.error ?? environment.error ?? "Keychain session restore") }
            if let restored = environment.authentication {
                if let llm { try await NativeLLMDiagnostics.verify(llm, session: restored) }
                else { try await NativeReviewPlan.requireNoLLM(client: AuthenticatedBackendClient(session: restored)) }
            }
            if plan.logHistoryReview, let restored = environment.authentication {
                let restarted = try await NativeLogHistoryDiagnostics.restartWithActiveStream(environment: environment, session: restored)
                try await NativeLogHistoryDiagnostics.verify(session: restarted, directory: directory)
                result["native_log_stream_cancelled_on_vm_stop_and_replayed_after_restart"] = true
                result["native_log_stream_heartbeat_received"] = true
                result["native_log_history_restarted_and_read_back"] = true
            }
            if CommandLine.arguments.contains("--dashboard-diagnostics"), let restored = environment.authentication {
                try await NativeDashboardDiagnostics.collect(session: restored, directory: directory)
                result["native_dashboard_nonempty_endpoints_and_metrics"] = true
            }
            if plan.skillVisibility, let restored = environment.authentication {
                try await verifySkillFixture(session: restored, expectedVisible: false, remove: false)
                result["native_seeded_skill_removal_survived_restart"] = true
            }
            if llm != nil { result["native_llm_restart_persistence"] = true }
            else { result["native_review_no_llm_after_restart"] = true }
            result["real_keychain_session_restored_after_vm_restart"] = true
            guard var login = environment.authentication else { throw RuntimeError.integrity("native login state") }
            login.logout()
            guard login.phase == .needsLogin else { throw RuntimeError.integrity("Keychain logout") }
            await login.login(password: password, agreed: false)
            guard login.phase == .needsLogin, login.error != nil else { throw RuntimeError.integrity("native terms validation") }
            await login.login(password: "wrong", agreed: true)
            guard login.phase == .needsLogin, login.error != nil else { throw RuntimeError.integrity("native incorrect password") }
            await login.login(password: password, agreed: true)
            guard login.phase == .authenticated else { throw RuntimeError.integrity(login.error ?? "native login") }
            result["native_login_validation_and_real_auth"] = true
            if CommandLine.arguments.contains("--upload-diagnostics") || CommandLine.arguments.contains("--upload-limit-diagnostics") {
                try await NativeUploadDiagnostics.run(session: login, directory: directory, includeLimit: CommandLine.arguments.contains("--upload-limit-diagnostics"))
                result["native_authenticated_upload_and_content"] = true
            }
            if CommandLine.arguments.contains("--upload-cancellation-diagnostics") {
                login = try await NativeUploadCancellationDiagnostics.run(session: login, directory: directory, stopAndRestart: {
                    try await environment.stop()
                    guard environment.controller.state == .stopped, !environment.controller.hasMachine else { throw RuntimeError.integrity("transfer VM stopped") }
                    let interrupted = environment.controller.lastStopInterruptedTransferCount
                    await environment.start()
                    guard environment.controller.guestReady, let restored = environment.authentication, restored.phase == .authenticated else { throw RuntimeError.integrity("transfer VM restart authentication") }
                    return NativeUploadRestart(session: restored, interruptedTransfers: interrupted)
                })
                result["native_partial_upload_task_cancel_and_vm_stop"] = true
            }
            if CommandLine.arguments.contains("--chat-review") {
                _ = try await NativeChatHistoryDiagnostics.run(session: login, directory: directory)
                result["chat_review_fixture_seeded"] = true
            }
            let mentionIDs: [Int64]
            if CommandLine.arguments.contains("--mention-review") {
                mentionIDs = try await NativeMentionDiagnostics.run(session: login, directory: directory)
                result["native_citation_populated_pages"] = true
            } else { mentionIDs = [] }
            if let reference = toolRunReference {
                let client = AuthenticatedBackendClient(session: login)
                let service = ToolRunService(client: client)
                let initial = try await service.list()
                guard initial.total == 0, initial.commands.isEmpty else {
                    throw RuntimeError.integrity("fresh tool-run review required")
                }
                try await ToolRunDiagnosticFixture.seed(client: client, reference: reference)
                let populated = try await service.list()
                guard populated.total == 54, populated.commands.count == 50 else {
                    throw RuntimeError.integrity("tool-run review seed count")
                }
                result["tool_run_fixture_rows"] = populated.total
                if plan.toolRunCancellation {
                    try Data().write(to: directory.appendingPathComponent("tool-run-cancellation-ready"))
                    try await waitForReviewMarker(directory.appendingPathComponent("tool-run-cancellation-start"))
                    try await verifyToolRunDeparture(environment: environment, client: client,
                                                     reference: reference, directory: directory)
                    result["tool_run_departure_cancelled_while_guest_locked"] = true
                }
                if plan.toolRunFailure {
                    faultToRestore = reference
                    try await ToolRunDiagnosticFixture.setHistoryUnavailable(true, client: client, reference: reference)
                    do {
                        _ = try await service.list()
                        throw RuntimeError.integrity("tool-run failure did not reach the API")
                    } catch BackendAPIError.status(500) {
                        result["tool_run_failure_status"] = 500
                    }
                    try Data().write(to: directory.appendingPathComponent("tool-run-failure-ready"))
                    try await waitForReviewMarker(directory.appendingPathComponent("tool-run-failure-restore"))
                    try await ToolRunDiagnosticFixture.setHistoryUnavailable(false, client: client, reference: reference)
                    let restored = try await service.list()
                    guard restored.total == 54, restored.commands.count == 50 else {
                        throw RuntimeError.integrity("tool-run review recovery")
                    }
                    faultToRestore = nil
                    result["tool_run_recovery_rows"] = restored.total
                }
            }
            try await Task.sleep(for: .milliseconds(300))
            if plan.mcpTaskReview {
                try await NativeMCPTaskDiagnostics.seed(session: login, directory: directory)
                try await environment.stop()
                await environment.start()
                guard let restored = environment.authentication, restored.phase == .authenticated else { throw RuntimeError.integrity("MCP fixture restart authentication") }
                login = restored
                try await NativeMCPTaskDiagnostics.collect(session: login, directory: directory)
                result["native_mcp_terminal_tasks_no_profiles"] = true
            }
            if plan.assetReview {
                let stage = directory.appendingPathComponent("native-asset-stage")
                try Data("seeding\n".utf8).write(to: stage, options: .atomic)
                try await NativeAssetDiagnostics.seed(session: login, directory: directory)
                try Data("seeded\n".utf8).write(to: stage, options: .atomic)
                result["native_asset_fixture_rows"] = 26
            }
            result["authenticated_content_snapshot"] = try capture(to: directory.appendingPathComponent("native-authenticated.png"))
            if CommandLine.arguments.contains("--native-review") {
                // Keep this disposable authenticated fixture open for external UI testing.
                // The fixed completion marker cannot execute commands or access the guest.
                try JSONSerialization.data(withJSONObject: ["ready": true, "fixture_only": true], options: [.sortedKeys]).write(to: directory.appendingPathComponent("native-review-ready.json"))
                let finish = directory.appendingPathComponent("native-review-finish")
                var attachedLogStream = false
                var detachedLogStream = false
                try await waitForReviewMarker(finish) {
                    guard plan.logHistoryReview, !detachedLogStream else { return }
                    let count = environment.controller.diagnosticLogStreamsInFlight
                    if count == 1, !attachedLogStream {
                        attachedLogStream = true
                        try Data().write(to: directory.appendingPathComponent("native-log-stream-attached"))
                    } else if count == 0, attachedLogStream {
                        detachedLogStream = true
                        try Data().write(to: directory.appendingPathComponent("native-log-stream-detached"))
                    }
                }
                if plan.logHistoryReview {
                    result["native_log_stream_view_attached"] = attachedLogStream
                    result["native_log_stream_view_detached"] = detachedLogStream
                }
            }
            if !userBodyIDs.isEmpty {
                try await NativeUserBodyDiagnostics.cleanup(client: AuthenticatedBackendClient(session: login), ids: userBodyIDs)
                userBodyIDs = []
                result["native_user_body_fixture_cleaned"] = true
            }
            if !mentionIDs.isEmpty {
                try await NativeMentionDiagnostics.cleanup(mentionIDs, session: login)
                result["native_citation_fixture_cleaned"] = true
            }
            login.logout()
            guard login.phase == .needsLogin, login.error == nil else { throw RuntimeError.integrity("Keychain fixture cleanup") }
            result["temporary_keychain_item_removed"] = true
            try await environment.stop()
            result["app_owned_backend_stopped"] = environment.controller.state == .stopped
            let starting = Task { await environment.start() }
            for _ in 0..<300 {
                if environment.controller.state == .running || environment.controller.state == .failed { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            try await environment.stop()
            await starting.value
            guard environment.controller.state == .stopped else { throw RuntimeError.integrity("startup cancellation shutdown") }
            result["cooperative_stop_during_boot"] = true
        } catch {
            result["diagnostics_failed"] = true
            if let reference = faultToRestore, let session = environment.authentication, session.phase == .authenticated {
                let restore = Task { @MainActor in
                    let client = AuthenticatedBackendClient(session: session)
                    try await ToolRunDiagnosticFixture.setHistoryUnavailable(false, client: client, reference: reference)
                    return try await ToolRunService(client: client).list().total == 54
                }
                result["tool_run_fault_cleanup_restored"] = (try? await restore.value) == true
            }
            if !userBodyIDs.isEmpty {
                let client: (any BackendJSONTransport)?
                if let session = environment.authentication, session.phase == .authenticated {
                    client = AuthenticatedBackendClient(session: session)
                } else { client = nil }
                let cleaned = await cleanupUserBodyAfterFailure(client: client, ids: userBodyIDs)
                result["native_user_body_fixture_cleaned"] = cleaned
                if !cleaned { result["native_user_body_cleanup_failed"] = true }
            }
            try? Data(error.localizedDescription.utf8).write(to: directory.appendingPathComponent("error.txt"))
            environment.authentication?.logout()
            try? await environment.forceStop()
        }
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("native-results.json"))
        }
        if !environment.controller.hasMachine {
            NSApp.terminate(nil)
        }
    }
    private static func verifyToolRunDeparture(environment: DesktopRuntime, client: AuthenticatedBackendClient,
                                                reference: ToolRunDiagnosticFixture.Reference, directory: URL) async throws {
        let runtime = environment.controller
        let hold = Task { try await ToolRunDiagnosticFixture.holdHistoryReads(client: client, reference: reference) }
        defer { hold.cancel() }
        for waiting in [false, true] {
            var witnessed = false
            for _ in 0..<(waiting ? 160 : 50) {
                if (!waiting || runtime.diagnosticToolRunReadsInFlight == 1),
                   try await ToolRunDiagnosticFixture.historyReadWitness(waiting: waiting, client: client, reference: reference) {
                    witnessed = true
                    break
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard witnessed else { throw RuntimeError.integrity("tool-run departure lock witness") }
            try Data().write(to: directory.appendingPathComponent(waiting ? "tool-run-read-blocked" : "tool-run-lock-held"))
        }
        for _ in 0..<60 {
            if runtime.diagnosticToolRunReadsInFlight == 0 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard runtime.diagnosticToolRunReadsInFlight == 0,
              try await ToolRunDiagnosticFixture.historyReadWitness(waiting: false, client: client, reference: reference) else {
            throw RuntimeError.integrity("tool-run read did not cancel before guest lock release")
        }
        try Data().write(to: directory.appendingPathComponent("tool-run-read-cancelled"))
        try await hold.value
        guard try await ToolRunService(client: client).list().total == 54 else {
            throw RuntimeError.integrity("tool-run departure recovery")
        }
    }

    private static func waitForReviewMarker(_ marker: URL, poll: (() throws -> Void)? = nil) async throws {
        for _ in 0..<900 {
            if FileManager.default.fileExists(atPath: marker.path) { return }
            try poll?()
            try await Task.sleep(for: .seconds(1))
        }
        guard FileManager.default.fileExists(atPath: marker.path) else {
            throw RuntimeError.timeout("external native fixture review")
        }
    }
    private static func verifySkillFixture(session: AuthenticationSession, expectedVisible: Bool, remove: Bool) async throws {
        struct Health: Decodable { let version: String }
        let client = AuthenticatedBackendClient(session: session)
        let health = try await client.send(method: "GET", path: "/api/health", body: nil, bearer: nil)
        guard health.status == 200,
              try BackendJSONCoding.decode(Health.self, from: health.body).version == "artex-mac-e75ae371-cloud7" else {
            throw RuntimeError.integrity("skill visibility candidate version")
        }
        let service = AgentCatalogService(client: client)
        let details = try await service.promptDetails(key: "worker")
        guard let id = details.backendID else { throw RuntimeError.integrity("skill visibility agent identity") }
        let editor = AgentVisibilityEditor(key: "worker", service: service)
        let target = AgentVisibilityTarget.skill("api-recon")
        await editor.load(.skill)
        guard editor.canEdit, editor.resources.contains(where: { $0.id == target }),
              editor.contains(target) == expectedVisible else {
            throw RuntimeError.integrity("seeded skill visibility")
        }
        if remove {
            await editor.set(target, visible: false, agentID: id)
            guard editor.canEdit, !editor.contains(target) else {
                throw RuntimeError.integrity("remove seeded skill visibility")
            }
        }
    }

    static func cleanupUserBodyAfterFailure(client: (any BackendJSONTransport)?, ids: [Int64]) async -> Bool {
        guard !ids.isEmpty else { return true }
        guard let client else { return false }
        do { try await NativeUserBodyDiagnostics.cleanup(client: client, ids: ids); return true }
        catch { return false }
    }
    private static func capture(to url: URL) throws -> Bool {
        let candidates = NSApp.windows.filter { $0.isVisible && $0.frame.width >= 980 && $0.frame.height >= 680 }
        guard candidates.count == 1, let view = candidates[0].contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw RuntimeError.integrity("native window capture") }
        candidates[0].effectiveAppearance.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: bitmap) }
        guard let png = bitmap.representation(using: .png, properties: [:]), bitmap.pixelsWide > 900, bitmap.pixelsHigh > 600 else { throw RuntimeError.integrity("native rendered content") }
        try png.write(to: url)
        return true
    }
}
#endif
