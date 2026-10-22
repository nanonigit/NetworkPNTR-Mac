import ArtexCore
import SwiftUI

struct DashboardView: View {
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
                        Text("Dashboard").font(.largeTitle.bold())
                        Text("タスク・使用量・検出結果と隔離環境の状態").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("再読み込み", systemImage: "arrow.clockwise") { Task { await store.refreshAll() } }
                        .keyboardShortcut("r", modifiers: .command)
                }
                loadStatus("タスク", state: store.tasks)
                loadStatus("活動・システム", state: store.fast)
                loadStatus("モデル・資産・通信", state: store.slow)
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
                    ContentUnavailableView("集計を確認できません", systemImage: "exclamationmark.triangle", description: Text("取得済みデータに不整合があります。再読み込みしてください。"))
                }
            }.padding(28)
        }
        .navigationTitle("Dashboard")
        .task { await store.run() }
        .onDisappear { store.stop() }
    }
    @ViewBuilder private func loadStatus<T>(_ title: String, state: DashboardLoadState<T>) -> some View {
        if let error = state.error {
            VStack(alignment: .leading, spacing: 4) {
                Label(title + "：" + error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                if let updatedAt = state.updatedAt {
                    Text("前回取得した内容を表示中（\(updatedAt.formatted(date: .omitted, time: .standard))）").foregroundStyle(.secondary)
                } else { Text("まだ取得できていません。").foregroundStyle(.secondary) }
            }.font(.callout)
        } else if state.isLoading && state.value == nil {
            ProgressView(title + "を読み込み中").controlSize(.small)
        }
    }
    private func summary(_ metrics: DashboardMetrics) -> some View {
        let tasks = store.tasks.value
        let fast = store.fast.value
        let slow = store.slow.value
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), alignment: .top)], spacing: 12) {
            DashboardSummaryCard(title: "実行中のタスク", value: tasks.map { _ in "\(metrics.runningTasks) / \(tasks!.count)" },
                                 detail: tasks.map { "一時停止 \($0.filter { $0.status == "paused" }.count) · 完了 \($0.filter { $0.status == "done" }.count)" }, icon: "checklist", color: .blue)
            DashboardSummaryCard(title: "検出結果", value: fast.map { "\($0.findings.count)" },
                                 detail: fast.map { _ in "Critical \(metrics.severityCounts["critical", default: 0]) · High \(metrics.severityCounts["high", default: 0]) · Medium \(metrics.severityCounts["medium", default: 0]) · Low \(metrics.severityCounts["low", default: 0])" }, icon: "shield", color: .orange)
            DashboardSummaryCard(title: "資産", value: slow.map { _ in "\(metrics.assetTotal)" }, detail: slow.map { "\($0.assetCounts.filter { $0.value > 0 }.count) 種類" }, icon: "shippingbox", color: .green)
            DashboardSummaryCard(title: "通信サンプル", value: slow.map { "\($0.traffic.count)" }, detail: fast.map { $0.settings.trafficCapture ? "キャプチャ ON · 最新50件まで" : "キャプチャ OFF · 最新50件まで" }, icon: "network", color: .purple)
            DashboardSummaryCard(title: "トークン", value: store.tokensAvailable ? DashboardFormat.number(metrics.tokens.total) : nil,
                                 detail: store.tokensAvailable ? "入力 \(DashboardFormat.number(metrics.tokens.input)) · 出力 \(DashboardFormat.number(metrics.tokens.output))" : nil, icon: "chart.bar", color: .cyan)
        }
    }
}

enum DashboardDestination { case feature(String), task(String) }
struct DashboardSummaryCard: View {
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
                Text(detail ?? "取得待ち").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
