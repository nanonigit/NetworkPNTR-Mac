import ArtexCore
import SwiftUI

struct DashboardAssetsPanel: View {
    let data: DashboardSlowData?
    let metrics: DashboardMetrics
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Label("資産の分布", systemImage: "shippingbox").font(.headline)
                if data != nil {
                    if metrics.assetTypes.isEmpty { Text("資産はありません。").foregroundStyle(.secondary) }
                    ForEach(metrics.assetTypes) { item in
                        HStack {
                            Text(item.name).font(.caption).frame(width: 80, alignment: .leading)
                            ProgressView(value: Double(item.count) / Double(metrics.assetTypes.first?.count ?? 1))
                            Text("\(item.count)").font(.caption).monospacedDigit()
                        }.accessibilityElement(children: .combine)
                    }
                    Divider(); Text("合計 \(metrics.assetTotal) ノード").font(.caption).foregroundStyle(.secondary)
                } else { DashboardWaiting() }
            }.frame(maxWidth: .infinity, alignment: .topLeading).padding(12)
        }
    }
}
struct DashboardTrafficPanel: View {
    let data: DashboardSlowData?
    let metrics: DashboardMetrics
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Label("通信ステータス", systemImage: "network").font(.headline)
                if let data {
                    Text("最新50件までのサンプル · \(data.traffic.count) リクエスト").font(.caption).foregroundStyle(.secondary)
                    if metrics.trafficBuckets.isEmpty { Text("通信データはありません。").foregroundStyle(.secondary) }
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
    let fast: DashboardFastData?
    let slow: DashboardSlowData?
    let navigate: (DashboardDestination) -> Void
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Label("システムの状態", systemImage: "shield.lefthalf.filled").font(.headline)
                if let fast {
                    LabeledContent("LLM", value: fast.stats.llmConfigured ? "設定済み" : "未設定")
                    LabeledContent("通信キャプチャ", value: fast.settings.trafficCapture ? "ON" : "OFF")
                } else { DashboardWaiting() }
                if let slow {
                    if let active = slow.profiles.first(where: \.isDefault) {
                        LabeledContent("有効なモデル") { Text(active.model).font(.caption.monospaced()).textSelection(.enabled) }
                    }
                }
                if let fast {
                    Divider()
                    if fast.pending.isEmpty { Label("承認待ちの操作はありません", systemImage: "checkmark.shield").font(.caption).foregroundStyle(.secondary) }
                    else {
                        Text("承認待ち \(fast.pending.count) 件").font(.callout.bold()).foregroundStyle(.orange)
                        ForEach(Array(fast.pending.prefix(3))) { pending in
                            Button { navigate(.feature("approvals")) } label: {
                                HStack {
                                    VStack(alignment: .leading) { Text(pending.toolName); Text(pending.agentName).font(.caption).foregroundStyle(.secondary) }
                                    Spacer(); Image(systemName: "arrow.up.right")
                                }
                            }.buttonStyle(.bordered)
                        }
                        if fast.pending.count > 3 { Button("ほか \(fast.pending.count - 3) 件を表示") { navigate(.feature("approvals")) } }
                    }
                }
            }.font(.callout).frame(maxWidth: .infinity, alignment: .topLeading).padding(12)
        }
    }
}
