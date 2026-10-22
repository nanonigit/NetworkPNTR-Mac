import ArtexCore
import SwiftUI

struct DashboardActivityPanel: View {
    let data: DashboardFastData?
    let metrics: DashboardMetrics
    let navigate: (DashboardDestination) -> Void
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("最近の活動", systemImage: "waveform.path").font(.headline)
                    Spacer(); Button("タスクを見る") { navigate(.feature("tasks")) }
                }
                if let data {
                    Text("\(data.activity.filter { $0.kind != "usage" }.count) イベント（最新30件の取得結果）").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        ForEach(["tool_use", "tool_result", "text", "thinking", "result"], id: \.self) { kind in
                            if let count = metrics.activityCounts[kind], count > 0 {
                                Text("\(kind) \(count)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if metrics.recentActivity.isEmpty { Text("活動はありません。").foregroundStyle(.secondary) }
                    ForEach(metrics.recentActivity) { row in
                        HStack(alignment: .top) {
                            Circle().fill(row.worker == "planner" ? Color.purple : row.worker == "mainagent" ? .cyan : .blue).frame(width: 7, height: 7).padding(.top, 5)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack { Text(row.worker).fontWeight(.semibold); Text(row.kindLabel).foregroundStyle(.secondary) }.font(.caption)
                                Text(row.summary).font(.callout).lineLimit(3).help(row.summary)
                                DashboardTimestamp(value: row.ts)
                            }.textSelection(.enabled)
                        }
                        Divider()
                    }
                } else { DashboardWaiting() }
            }.frame(maxWidth: .infinity, alignment: .topLeading).padding(12)
        }
    }
}
struct DashboardFindingsPanel: View {
    let data: DashboardFastData?
    let metrics: DashboardMetrics
    let navigate: (DashboardDestination) -> Void
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("最近の検出結果", systemImage: "shield").font(.headline)
                    Spacer(); Button("すべて表示") { navigate(.feature("findings")) }
                }
                if data != nil {
                    if metrics.recentFindings.isEmpty { Text("検出結果はありません。").foregroundStyle(.secondary) }
                    ForEach(metrics.recentFindings) { finding in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(finding.severity.uppercased()).font(.caption.bold()).foregroundStyle(finding.severity == "critical" || finding.severity == "high" ? .red : .orange)
                                Text(finding.vulnclass).font(.callout.bold())
                                Spacer()
                            }
                            Text(finding.summary).font(.callout).lineLimit(3).help(finding.summary)
                            if let task = finding.taskDescription, !task.isEmpty { Text(task).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            DashboardTimestamp(value: finding.ts)
                        }.textSelection(.enabled)
                        Divider()
                    }
                } else { DashboardWaiting() }
            }.frame(maxWidth: .infinity, alignment: .topLeading).padding(12)
        }
    }
}
struct DashboardTasksPanel: View {
    let tasks: [DashboardTask]?
    let metrics: DashboardMetrics
    let navigate: (DashboardDestination) -> Void
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("最近のタスク", systemImage: "checklist").font(.headline)
                    Spacer(); Button("すべて表示") { navigate(.feature("tasks")) }
                }
                if let tasks {
                    if tasks.isEmpty { Text("タスクはありません。").foregroundStyle(.secondary) }
                    else {
                        ScrollView(.horizontal) {
                            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                                GridRow { Text("タスク"); Text("状態"); Text("実行モード"); Text("目標"); Text("処理中"); Text("最終活動") }.font(.caption.bold()).foregroundStyle(.secondary)
                                ForEach(metrics.recentTasks) { task in
                                    GridRow(alignment: .top) {
                                        Button { navigate(.task(task.id)) } label: {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(task.description).lineLimit(1).help(task.description)
                                                Text(task.id).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                                            }.frame(width: 240, alignment: .leading)
                                        }.buttonStyle(.link).accessibilityLabel("タスク詳細：" + task.description)
                                        Text(task.status).foregroundStyle(task.status == "running" ? .green : .secondary)
                                        Text(task.engineMode ?? "idle").foregroundStyle(.secondary)
                                        if let total = task.goalsTotal, total > 0 {
                                            VStack(alignment: .leading, spacing: 4) {
                                                ProgressView(value: min(1, max(0, Double(task.goalsMet ?? 0) / Double(total)))).frame(width: 65)
                                                Text("\(task.goalsMet ?? 0)/\(total)").font(.caption)
                                            }
                                        } else { Text("—") }
                                        Text((task.inFlight ?? 0) > 0 ? String(task.inFlight!) : "—").monospacedDigit()
                                        if task.activityUnix != 0 { Text(Date(timeIntervalSince1970: Double(task.activityUnix)), style: .relative).font(.caption).foregroundStyle(.secondary) }
                                        else { Text("—") }
                                    }
                                }
                            }.font(.callout).padding(.bottom, 4)
                        }
                    }
                } else { DashboardWaiting() }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
        }
    }
}
struct DashboardWaiting: View {
    var body: some View { Text("データ取得待ち").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 70) }
}
struct DashboardTimestamp: View {
    let value: String
    var body: some View {
        if let date = DashboardFormat.date(value) {
            Text(date, style: .relative).font(.caption2).foregroundStyle(.secondary).help(value)
        } else { Text(value).font(.caption2).foregroundStyle(.secondary) }
    }
}
