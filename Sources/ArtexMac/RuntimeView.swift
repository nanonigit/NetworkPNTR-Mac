import ArtexCore
import SwiftUI

struct RuntimeView: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    private func f(_ key: AppStringKey, _ values: [String: String]) -> String { AppStrings.formatted(key, language: language, values: values) }
    let environment: DesktopRuntime
    private var runtime: VMController { environment.controller }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(s(.runtimeUITitle)).font(.largeTitle.bold())
                    Text(s(.runtimeUISubtitle)).foregroundStyle(.secondary)
                }
                GroupBox {
                    HStack(spacing: 16) {
                        Image(systemName: runtime.guestReady ? "checkmark.shield.fill" : "shield.lefthalf.filled").font(.system(size: 32)).foregroundStyle(runtime.guestReady ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(runtime.guestReady ? s(.runtimeUIReady) : runtime.state == .running ? s(.runtimeUIARTEXStarting) : f(.runtimeUIState, ["state": RuntimeLabels.state(runtime.state, language: language)])).font(.headline)
                            Text(s(.runtimeUIIsolation)).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if runtime.state == .starting || runtime.state == .stopping { ProgressView().controlSize(.small) }
                    }.padding(12)
                }
                HStack {
                    Button(s(.runtimeUIStart), systemImage: "play.fill") {
                        Task { await environment.start() }
                    }.buttonStyle(.borderedProminent).disabled(environment.isStarting || !runtime.mayStart).keyboardShortcut("r", modifiers: [.command, .shift])
                    Button(s(.runtimeUIStop), systemImage: "stop.fill") {
                        Task { do { try await environment.stop() } catch { /* VMController presents the failure. */ } }
                    }.disabled(!runtime.state.canStop)
                    if runtime.hasMachine && (runtime.state == .failed || runtime.state == .stopping) {
                        Button(s(.runtimeUIForceStop), role: .destructive) { Task { do { try await environment.forceStop() } catch { /* Visible in runtime.lastError. */ } } }
                    }
                }
                if let error = (environment.failure ?? runtime.failure)?.text(language: language) { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).textSelection(.enabled) }
                GroupBox(s(.runtimeUIEnvironment)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(s(.runtimeUIVirtualization), systemImage: "cpu")
                        Label(s(.runtimeUIIntegrity), systemImage: "checkmark.seal")
                        Label(s(.runtimeUIPersistence), systemImage: "terminal")
                        Text(s(.runtimeUIHelp))
                            .font(.callout).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                if !runtime.guestLog.isEmpty {
                    GroupBox(s(.runtimeUIGuestLog)) {
                        Text(runtime.guestLog).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                }
            }.padding(32).frame(maxWidth: 940, alignment: .leading)
        }
        .groupBoxStyle(RuntimePanelStyle())
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(s(.runtime))
    }
}

private struct RuntimePanelStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            configuration.label.font(.headline)
            configuration.content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }
}
