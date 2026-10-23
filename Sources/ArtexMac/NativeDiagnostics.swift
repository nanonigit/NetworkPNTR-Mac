#if DEBUG
import AppKit
import ArtexCore
import Foundation

/// Exercises this app's production services with an isolated fixture disk and Keychain item.
/// Internal rendering/service diagnostics do not replace external native click acceptance.
@MainActor enum NativeDiagnostics {
    static func run(environment: DesktopRuntime, directory: URL) async {
        var result: [String: Any] = ["ui_click_workflow_verified": false, "visual_acceptance": "pending external native automation"]
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
            let llm = try await NativeLLMDiagnostics.run(session: authentication, directory: directory)
            result["native_llm_three_formats_crud_key_preservation_pool_retry"] = true
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
            try await environment.stop()
            await environment.start()
            guard environment.authentication?.phase == .authenticated else { throw RuntimeError.integrity(environment.authentication?.error ?? environment.error ?? "Keychain session restore") }
            if let restored = environment.authentication { try await NativeLLMDiagnostics.verify(llm, session: restored) }
            if CommandLine.arguments.contains("--dashboard-diagnostics"), let restored = environment.authentication {
                try await NativeDashboardDiagnostics.collect(session: restored, directory: directory)
                result["native_dashboard_nonempty_endpoints_and_metrics"] = true
            }
            result["native_llm_restart_persistence"] = true
            result["real_keychain_session_restored_after_vm_restart"] = true
            guard let login = environment.authentication else { throw RuntimeError.integrity("native login state") }
            login.logout()
            guard login.phase == .needsLogin else { throw RuntimeError.integrity("Keychain logout") }
            await login.login(password: password, agreed: false)
            guard login.phase == .needsLogin, login.error != nil else { throw RuntimeError.integrity("native terms validation") }
            await login.login(password: "wrong", agreed: true)
            guard login.phase == .needsLogin, login.error != nil else { throw RuntimeError.integrity("native incorrect password") }
            await login.login(password: password, agreed: true)
            guard login.phase == .authenticated else { throw RuntimeError.integrity(login.error ?? "native login") }
            result["native_login_validation_and_real_auth"] = true
            if CommandLine.arguments.contains("--chat-review") {
                _ = try await NativeChatHistoryDiagnostics.run(session: login, directory: directory)
                result["chat_review_fixture_seeded"] = true
            }
            let mentionIDs: [Int64]
            if CommandLine.arguments.contains("--mention-review") {
                mentionIDs = try await NativeMentionDiagnostics.run(session: login, directory: directory)
                result["native_citation_populated_pages"] = true
            } else { mentionIDs = [] }
            try await Task.sleep(for: .milliseconds(300))
            result["authenticated_content_snapshot"] = try capture(to: directory.appendingPathComponent("native-authenticated.png"))
            if CommandLine.arguments.contains("--native-review") {
                // Keep this disposable authenticated fixture open for external UI testing.
                // The fixed completion marker cannot execute commands or access the guest.
                try JSONSerialization.data(withJSONObject: ["ready": true, "fixture_only": true], options: [.sortedKeys]).write(to: directory.appendingPathComponent("native-review-ready.json"))
                let finish = directory.appendingPathComponent("native-review-finish")
                for _ in 0..<900 {
                    if FileManager.default.fileExists(atPath: finish.path) { break }
                    try await Task.sleep(for: .seconds(1))
                }
                guard FileManager.default.fileExists(atPath: finish.path) else { throw RuntimeError.timeout("external native fixture review") }
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
