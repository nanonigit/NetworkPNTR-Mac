import NetworkPNTRCore
import SwiftUI

struct LocalConnectionView: View {
    let environment: DesktopRuntime
    let showRuntime: () -> Void
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    private var busy: Bool { environment.isStarting || environment.isReconnecting }
    private var failed: Bool {
        environment.failure != nil || environment.controller.state == .failed ||
        [.unavailable, .needsSetup, .needsLogin].contains(environment.authentication?.phase)
    }
    private var stopped: Bool { environment.controller.state == .stopped && !busy }
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: failed ? "exclamationmark.triangle" : "network")
                .font(.system(size: 38)).foregroundStyle(.secondary)
            Text(s(failed ? .localSessionUnavailable : stopped ? .localSessionStopped : .localSessionPreparing))
                .font(.title2.bold())
            if busy || (!failed && !stopped) {
                ProgressView().accessibilityLabel(s(.localSessionPreparing))
            } else {
                if failed { Text(s(.localSessionUnavailableDetail)).foregroundStyle(.secondary) }
                HStack {
                    if environment.controller.guestReady || environment.controller.mayStart {
                        Button(s(stopped ? .localSessionStart : .localSessionRetry)) {
                            Task { await environment.retryLocalConnection() }
                        }.buttonStyle(.borderedProminent).accessibilityIdentifier("local-session-retry")
                    }
                    Button(s(.runtime), action: showRuntime)
                }
            }
        }
        .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("local-session-status")
    }
}
