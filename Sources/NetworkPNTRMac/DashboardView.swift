import NetworkPNTRCore
import SwiftUI

struct DashboardView: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    private func f(_ key: AppStringKey, _ values: [String: String]) -> String { AppStrings.formatted(key, language: language, values: values) }
    @State private var store: DashboardStore
    let navigate: (DashboardDestination) -> Void
    init(session: AuthenticationSession, navigate: @escaping (DashboardDestination) -> Void) {
        _store = State(initialValue: DashboardStore(service: DashboardService(client: AuthenticatedBackendClient(session: session))))
        self.navigate = navigate
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(s(.dashboardUITitle)).font(.largeTitle.bold())
                        Text(s(.dashboardUIDescription)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(s(.dashboardUIReload), systemImage: "arrow.clockwise") { Task { await store.refreshAll() } }
                        .keyboardShortcut("r", modifiers: .command)
                }
                loadStatus(s(.dashboardUITasks), state: store.tasks)
                loadStatus(s(.dashboardUIActivitySystem), state: store.fast)
                loadStatus(s(.dashboardUIModelsAssetsTraffic), state: store.slow)
                if let metrics = try? store.metrics() {
                    summary(metrics)
                    DashboardTokensView(store: store, metrics: metrics)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), alignment: .top)], alignment: .leading, spacing: 16) {
                        DashboardActivityPanel(data: store.fast.value, metrics: metrics, navigate: navigate)
                        DashboardFindingsPanel(data: store.fast.value, metrics: metrics, navigate: navigate)
                    }
                    DashboardTasksPanel(tasks: store.tasks.value, metrics: metrics, navigate: navigate)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), alignment: .top)], alignment: .leading, spacing: 16) {
                        DashboardAssetsPanel(data: store.slow.value, metrics: metrics)
                        DashboardTrafficPanel(data: store.slow.value, metrics: metrics)
                        DashboardSystemPanel(fast: store.fast.value, slow: store.slow.value, navigate: navigate)
                    }
                } else {
                    ContentUnavailableView(s(.dashboardUIInvalidTitle), systemImage: "exclamationmark.triangle", description: Text(s(.dashboardUIInvalidHelp)))
                }
            }.padding(28)
        }
        .navigationTitle(s(.dashboardUITitle))
        .task { await store.run() }
        .onDisappear { store.stop() }
    }
    @ViewBuilder private func loadStatus<T>(_ title: String, state: DashboardLoadState<T>) -> some View {
        if let error = state.failure?.text(language: language) {
            VStack(alignment: .leading, spacing: 4) {
                Label(f(.dashboardUIFailureGroup, ["group": title, "error": error]), systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                if let updatedAt = state.updatedAt {
                    Text(f(.dashboardUIStale, ["time": updatedAt.formatted(Date.FormatStyle(date: .omitted, time: .standard).locale(language.locale))])).foregroundStyle(.secondary)
                } else { Text(s(.dashboardUINotLoaded)).foregroundStyle(.secondary) }
            }.font(.callout)
        } else if state.isLoading && state.value == nil {
            ProgressView(f(.dashboardUILoadingGroup, ["group": title])).controlSize(.small)
        }
    }
    private func summary(_ metrics: DashboardMetrics) -> some View {
        let tasks = store.tasks.value
        let fast = store.fast.value
        let slow = store.slow.value
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), alignment: .top)], spacing: 12) {
            DashboardSummaryCard(title: s(.dashboardUIRunningTasks), value: tasks.map { _ in "\(metrics.runningTasks) / \(tasks!.count)" },
                                 detail: tasks.map { f(.dashboardUITaskSummary, ["paused": String($0.filter { $0.status == "paused" }.count), "done": String($0.filter { $0.status == "done" }.count)]) }, icon: "checklist", color: .blue)
            DashboardSummaryCard(title: s(.dashboardUIFindings), value: fast.map { "\($0.findings.count)" },
                                 detail: fast.map { _ in f(.dashboardUISeveritySummary, ["critical": String(metrics.severityCounts["critical", default: 0]), "high": String(metrics.severityCounts["high", default: 0]), "medium": String(metrics.severityCounts["medium", default: 0]), "low": String(metrics.severityCounts["low", default: 0])]) }, icon: "shield", color: .orange)
            DashboardSummaryCard(title: s(.dashboardUIAssets), value: slow.map { _ in "\(metrics.assetTotal)" }, detail: slow.map { f(.dashboardUITypeCount, ["count": String($0.assetCounts.filter { $0.value > 0 }.count)]) }, icon: "shippingbox", color: .green)
            DashboardSummaryCard(title: s(.dashboardUITrafficSample), value: slow.map { "\($0.traffic.count)" }, detail: fast.map { $0.settings.trafficCapture ? s(.dashboardUICaptureOn) : s(.dashboardUICaptureOff) }, icon: "network", color: .purple)
            DashboardSummaryCard(title: s(.dashboardUITokens), value: store.tokensAvailable ? DashboardFormat.number(metrics.tokens.total) : nil,
                                 detail: store.tokensAvailable ? f(.dashboardUITokenSummary, ["input": DashboardFormat.number(metrics.tokens.input), "output": DashboardFormat.number(metrics.tokens.output)]) : nil, icon: "chart.bar", color: .cyan)
        }
    }
}

enum DashboardDestination { case feature(String), task(String) }
struct DashboardSummaryCard: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    let title: String
    let value: String?
    let detail: String?
    let icon: String
    let color: Color
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 9) {
                Label(title, systemImage: icon).font(.callout).foregroundStyle(color)
                Text(value ?? "—").font(.title2.bold()).monospacedDigit()
                Text(detail ?? s(.dashboardUIWaiting)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading).padding(8)
        }
    }
}
enum DashboardFormat {
    static func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0))) }
    static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}
