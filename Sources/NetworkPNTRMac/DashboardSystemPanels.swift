import NetworkPNTRCore
import SwiftUI

struct DashboardAssetsPanel: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    private func f(_ key: AppStringKey, _ values: [String: String]) -> String { AppStrings.formatted(key, language: language, values: values) }
    let data: DashboardSlowData?
    let metrics: DashboardMetrics
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Label(s(.dashboardUIAssetDistribution), systemImage: "shippingbox").font(.headline)
                if data != nil {
                    if metrics.assetTypes.isEmpty { Text(s(.dashboardUINoAssets)).foregroundStyle(.secondary) }
                    ForEach(metrics.assetTypes) { item in
                        HStack {
                            Text(item.name).font(.caption).frame(width: 80, alignment: .leading)
                            ProgressView(value: Double(item.count) / Double(metrics.assetTypes.first?.count ?? 1))
                            Text("\(item.count)").font(.caption).monospacedDigit()
                        }.accessibilityElement(children: .combine)
                    }
                    Divider(); Text(f(.dashboardUIAssetTotal, ["count": String(metrics.assetTotal)])).font(.caption).foregroundStyle(.secondary)
                } else { DashboardWaiting() }
            }.frame(maxWidth: .infinity, alignment: .topLeading).padding(12)
        }
    }
}
struct DashboardTrafficPanel: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    private func f(_ key: AppStringKey, _ values: [String: String]) -> String { AppStrings.formatted(key, language: language, values: values) }
    let data: DashboardSlowData?
    let metrics: DashboardMetrics
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Label(s(.dashboardUITrafficStatus), systemImage: "network").font(.headline)
                if let data {
                    Text(f(.dashboardUIRequestCount, ["count": String(data.traffic.count)])).font(.caption).foregroundStyle(.secondary)
                    if metrics.trafficBuckets.isEmpty { Text(s(.dashboardUINoTraffic)).foregroundStyle(.secondary) }
                    ForEach(metrics.trafficBuckets) { bucket in
                        HStack {
                            Text("\(bucket.status)").font(.caption.monospaced()).frame(width: 55, alignment: .leading)
                            ProgressView(value: Double(bucket.count) / Double(metrics.trafficBuckets.map(\.count).max() ?? 1)).tint(bucket.status >= 400 ? .orange : .green)
                            Text("\(bucket.count)").font(.caption).monospacedDigit()
                        }.accessibilityElement(children: .combine)
                    }
                    Divider()
                    ForEach(metrics.recentTraffic) { row in
                        HStack(alignment: .top) {
                            Text("\(row.status)").foregroundStyle(row.status >= 400 ? .orange : .green).frame(width: 35, alignment: .leading)
                            Text(row.method).fontWeight(.semibold)
                            Text(row.host + String((URLComponents(string: row.url)?.percentEncodedPath ?? "").prefix(30))).lineLimit(1).help(row.url)
                            Spacer()
                        }.font(.caption.monospaced()).textSelection(.enabled)
                    }
                } else { DashboardWaiting() }
            }.frame(maxWidth: .infinity, alignment: .topLeading).padding(12)
        }
    }
}
struct DashboardSystemPanel: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    private func f(_ key: AppStringKey, _ values: [String: String]) -> String { AppStrings.formatted(key, language: language, values: values) }
    let fast: DashboardFastData?
    let slow: DashboardSlowData?
    let navigate: (DashboardDestination) -> Void
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Label(s(.dashboardUISystemStatus), systemImage: "shield.lefthalf.filled").font(.headline)
                if let fast {
                    LabeledContent("LLM", value: fast.stats.llmConfigured ? s(.dashboardUIConfigured) : s(.dashboardUINotConfigured))
                    LabeledContent(s(.dashboardUITrafficCapture), value: fast.settings.trafficCapture ? "ON" : "OFF")
                } else { DashboardWaiting() }
                if let slow {
                    if let active = slow.profiles.first(where: \.isDefault) {
                        LabeledContent(s(.dashboardUIActiveModel)) { Text(active.model).font(.caption.monospaced()).textSelection(.enabled) }
                    }
                }
                if let fast {
                    Divider()
                    if fast.pending.isEmpty { Label(s(.dashboardUINoPending), systemImage: "checkmark.shield").font(.caption).foregroundStyle(.secondary) }
                    else {
                        Text(f(.dashboardUIPendingCount, ["count": String(fast.pending.count)])).font(.callout.bold()).foregroundStyle(.orange)
                        ForEach(Array(fast.pending.prefix(3))) { pending in
                            Button { navigate(.feature("approvals")) } label: {
                                HStack {
                                    VStack(alignment: .leading) { Text(pending.toolName); Text(pending.agentName).font(.caption).foregroundStyle(.secondary) }
                                    Spacer(); Image(systemName: "arrow.up.right")
                                }
                            }.buttonStyle(.bordered)
                        }
                        if fast.pending.count > 3 { Button(f(.dashboardUIMorePending, ["count": String(fast.pending.count - 3)])) { navigate(.feature("approvals")) } }
                    }
                }
            }.font(.callout).frame(maxWidth: .infinity, alignment: .topLeading).padding(12)
        }
    }
}
