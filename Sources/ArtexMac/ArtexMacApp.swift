import AppKit
import ArtexCore
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var runtime: VMController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        #if DEBUG
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--phase1-diagnostics"), args.indices.contains(index + 1) {
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                guard let runtime else { return }
                await NativeDiagnostics.run(runtime: runtime, directory: URL(fileURLWithPath: args[index + 1]))
            }
        }
        #endif
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let runtime, runtime.hasMachine else { return .terminateNow }
        Task {
            do {
                if runtime.state.canStop { try await runtime.stop() }
                else { return sender.reply(toApplicationShouldTerminate: false) }
                sender.reply(toApplicationShouldTerminate: true)
            } catch { sender.reply(toApplicationShouldTerminate: false) }
        }
        return .terminateLater
    }
}
@main struct ArtexMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var runtime = VMController()
    var body: some Scene {
        WindowGroup("ARTEX Mac") {
            RootView(runtime: runtime)
                .onAppear { delegate.runtime = runtime }
                .frame(minWidth: 980, minHeight: 680)
        }
        .defaultSize(width: 1180, height: 800)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
