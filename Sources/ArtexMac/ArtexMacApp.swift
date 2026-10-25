import AppKit
import ArtexCore
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
    func applicationWillTerminate(_ notification: Notification) { menuLanguage?.stop() }
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
                .onAppear { delegate.environment = environment;delegate.updateMenuLanguage(language.language) }
                .onChange(of: language.language) { _, value in delegate.updateMenuLanguage(value) }
                .frame(minWidth: 980, minHeight: 680)
        }
        .defaultSize(width: 1180, height: 800)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
