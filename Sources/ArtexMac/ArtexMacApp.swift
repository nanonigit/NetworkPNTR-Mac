import AppKit
import ArtexCore
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var environment: DesktopRuntime?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        #if DEBUG
        if let directory = RuntimeFactory.diagnosticsDirectory {
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                guard let environment else { return }
                await NativeDiagnostics.run(environment: environment, directory: directory)
            }
        }
        #endif
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let environment, environment.controller.hasMachine else { return .terminateNow }
        Task {
            do {
                if environment.controller.state.canStop { try await environment.stop() }
                else { return sender.reply(toApplicationShouldTerminate: false) }
                sender.reply(toApplicationShouldTerminate: true)
            } catch { sender.reply(toApplicationShouldTerminate: false) }
        }
        return .terminateLater
    }
}
@main struct ArtexMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var environment = RuntimeFactory.make()
    @State private var language = AppLanguagePreferences()
    var body: some Scene {
        WindowGroup("ARTEX Mac") {
            RootView(environment: environment, language: language)
                .onAppear { delegate.environment = environment }
                .frame(minWidth: 980, minHeight: 680)
        }
        .defaultSize(width: 1180, height: 800)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
