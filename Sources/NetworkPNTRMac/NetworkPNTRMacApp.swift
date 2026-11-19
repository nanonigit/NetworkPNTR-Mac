import AppKit
import NetworkPNTRCore
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var environment: DesktopRuntime? { didSet { startDiagnosticsIfReady() } }
    #if DEBUG
    private var diagnosticAdmission = NativeDiagnosticAdmission()
    #endif
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
        diagnosticAdmission.didLaunch()
        #endif
        startDiagnosticsIfReady()
    }
    private func startDiagnosticsIfReady() {
        #if DEBUG
        guard let directory = RuntimeFactory.diagnosticsDirectory, let environment,
              diagnosticAdmission.admit(requested: true, hasEnvironment: true) else { return }
        Task {
            for _ in 0..<200 {
                if NSApp.windows.contains(where: { $0.isVisible }) { break }
                do { try await Task.sleep(for: .milliseconds(10)) } catch { return }
            }
            if CommandLine.arguments.contains("--local-session-diagnostics") {
                await NativeLocalSessionDiagnostics.run(environment: environment, directory: directory)
            } else { await NativeDiagnostics.run(environment: environment, directory: directory) }
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
    @State private var language = RuntimeFactory.makeLanguagePreferences()
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
