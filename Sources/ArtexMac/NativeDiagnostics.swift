#if DEBUG
import AppKit
import ArtexCore
import Foundation

/// Developer acceptance harness for this app's own VM service and rendered content view.
/// It does not control or capture other applications, and is absent from release builds.
@MainActor enum NativeDiagnostics {
    static func run(runtime: VMController, directory: URL) async {
        var result: [String: Any] = ["ui_click_workflow_verified": false, "visual_acceptance": "pending native automation; content snapshots do not replace real screen comparison"]
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            result["native_window_rendered"] = try capture(to: directory.appendingPathComponent("native-launch.png"))
            guard let resources = Bundle.main.resourceURL else { throw RuntimeError.integrity("bundle resources") }
            try await runtime.start(artifacts: resources.appendingPathComponent("Guest"), logs: directory.appendingPathComponent("guest"))
            for _ in 0..<600 {
                if runtime.guestReady || runtime.state == .failed { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard runtime.guestReady else { throw RuntimeError.timeout("native diagnostics readiness") }
            result["app_owned_vm_ready"] = true
            try await Task.sleep(for: .milliseconds(300))
            result["ready_content_snapshot"] = try capture(to: directory.appendingPathComponent("native-runtime.png"))
            try await runtime.stop()
            result["app_owned_vm_stopped"] = runtime.state == .stopped
            try await Task.sleep(for: .milliseconds(300))
            result["stopped_content_snapshot"] = try capture(to: directory.appendingPathComponent("native-stopped.png"))
        } catch {
            result["diagnostics_failed"] = true
            try? Data(error.localizedDescription.utf8).write(to: directory.appendingPathComponent("error.txt"))
            try? await runtime.forceStop()
        }
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("native-results.json"))
        }
    }
    private static func capture(to url: URL) throws -> Bool {
        let candidates = NSApp.windows.filter { $0.isVisible && $0.frame.width >= 980 && $0.frame.height >= 680 }
        guard candidates.count == 1,
              let view = candidates[0].contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw RuntimeError.integrity("native window capture") }
        candidates[0].effectiveAppearance.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: bitmap)
        }
        guard let png = bitmap.representation(using: .png, properties: [:]), bitmap.pixelsWide > 900, bitmap.pixelsHigh > 600 else { throw RuntimeError.integrity("native rendered content") }
        try png.write(to: url)
        return true
    }
}
#endif
