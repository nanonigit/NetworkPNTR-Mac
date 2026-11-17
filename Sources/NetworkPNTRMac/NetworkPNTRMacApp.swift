import AppKit
import NetworkPNTRCore
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var environment: DesktopRuntime?
    private var menuLanguage: AppMenuLanguageBridge?
    func updateMenuLanguage(_ language: AppLanguage) {
        if menuLanguage == nil {
            menuLanguage = AppMenuLanguageBridge {
                AppMenuContext(mainMenu: NSApp.mainMenu, windowsMenu: NSApp.windowsMenu, helpMenu: NSApp.helpMenu, servicesMenu: NSApp.servicesMenu)
            }
        }
        menuLanguage?.start(language: language)
    }
    func applicationWillTerminate(_ notification: Notification) { environment?.mcp.invalidateAll(); menuLanguage?.stop() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        menuLanguage?.refresh()
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
        guard let environment,
              environment.controller.hasMachine || !environment.mcp.connections.isEmpty || environment.mcp.isBusy else { return .terminateNow }
        Task {
            do {
                if !environment.controller.hasMachine { await environment.mcp.revokeAll() }
                else if environment.controller.state.canStop { try await environment.stop() }
                else { return sender.reply(toApplicationShouldTerminate: false) }
                sender.reply(toApplicationShouldTerminate: true)
            } catch { sender.reply(toApplicationShouldTerminate: false) }
        }
        return .terminateLater
    }
}
@main struct NetworkPNTRMacApp: App {
    private struct GuestLanguageSelection: Equatable {
        let language: AppLanguage
        let epoch: UUID?
    }

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var environment = RuntimeFactory.make()
    @State private var language = AppLanguagePreferences()
    @State private var guestLanguageSync = GuestOutputLanguageSync()
    @State private var trafficRetirements = TrafficBodyExportRetirement()
    var body: some Scene {
        WindowGroup("NetworkPNTR Mac") {
            RootView(environment: environment, language: language, trafficRetirements: trafficRetirements)
                .onAppear { delegate.environment = environment;delegate.updateMenuLanguage(language.language) }
                .onChange(of: language.language) { _, value in delegate.updateMenuLanguage(value) }
                .onChange(of: GuestLanguageSelection(language: language.language,
                                                      epoch: environment.authentication?.exportSessionGeneration), initial: true) { _, change in
                    guestLanguageSync.update(change.language, session: environment.authentication)
                }
                .frame(minWidth: 980, minHeight: 680)
        }
        .defaultSize(width: 1180, height: 800)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
