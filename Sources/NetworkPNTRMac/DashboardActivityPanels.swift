import NetworkPNTRCore
import SwiftUI

struct DashboardActivityPanel: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    private func f(_ key: AppStringKey, _ values: [String: String]) -> String { AppStrings.formatted(key, language: language, values: values) }
    let data: DashboardFastData?
    let metrics: DashboardMetrics
    let navigate: (DashboardDestination) -> Void
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(s(.dashboardUIRecentActivity), systemImage: "waveform.path").font(.headline)
                    Spacer(); Button(s(.dashboardUIViewTasks)) { navigate(.feature("tasks")) }
                }
                if let data {
                    Text(f(.dashboardUIEventCount, ["count": String(data.activity.filter { $0.kind != "usage" }.count)])).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        ForEach(["tool_use", "tool_result", "text", "thinking", "result"], id: \.self) { kind in
                            if let count = metrics.activityCounts[kind], count > 0 {
                                Text("\(DashboardLabels.text(kind, domain: .activity, language: language)) \(count)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if metrics.recentActivity.isEmpty { Text(s(.dashboardUINoActivity)).foregroundStyle(.secondary) }
                    ForEach(metrics.recentActivity) { row in
                        HStack(alignment: .top) {
                            Circle().fill(row.worker == "planner" ? Color.purple : row.worker == "mainagent" ? .cyan : .blue).frame(width: 7, height: 7).padding(.top, 5)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack { Text(row.worker).fontWeight(.semibold); Text(DashboardLabels.activity(kind: row.kind, tool: row.tool, language: language)).foregroundStyle(.secondary) }.font(.caption)
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
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    let data: DashboardFastData?
    let metrics: DashboardMetrics
    let navigate: (DashboardDestination) -> Void
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(s(.dashboardUIRecentFindings), systemImage: "shield").font(.headline)
                    Spacer(); Button(s(.dashboardUIViewAll)) { navigate(.feature("findings")) }
                }
                if data != nil {
                    if metrics.recentFindings.isEmpty { Text(s(.dashboardUINoFindings)).foregroundStyle(.secondary) }
                    ForEach(metrics.recentFindings) { finding in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(DashboardLabels.text(finding.severity, domain: .severity, language: language)).font(.caption.bold()).foregroundStyle(finding.severity == "critical" || finding.severity == "high" ? .red : .orange)
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
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    private func f(_ key: AppStringKey, _ values: [String: String]) -> String { AppStrings.formatted(key, language: language, values: values) }
    let tasks: [DashboardTask]?
    let metrics: DashboardMetrics
    let navigate: (DashboardDestination) -> Void
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(s(.dashboardUIRecentTasks), systemImage: "checklist").font(.headline)
                    Spacer(); Button(s(.dashboardUIViewAll)) { navigate(.feature("tasks")) }
                }
                if let tasks {
                    if tasks.isEmpty { Text(s(.dashboardUINoTasks)).foregroundStyle(.secondary) }
                    else {
                        ScrollView(.horizontal) {
                            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                                GridRow { Text(s(.dashboardUITasks)); Text(s(.dashboardUIStatus)); Text(s(.dashboardUIEngine)); Text(s(.dashboardUIGoals)); Text(s(.dashboardUIInFlight)); Text(s(.dashboardUILastActivity)) }.font(.caption.bold()).foregroundStyle(.secondary)
                                ForEach(metrics.recentTasks) { task in
                                    GridRow(alignment: .top) {
                                        Button { navigate(.task(task.id)) } label: {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(task.description).lineLimit(1).help(task.description)
                                                Text(task.id).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                                            }.frame(width: 240, alignment: .leading)
                                        }.buttonStyle(.link).accessibilityLabel(f(.dashboardUITaskDetail, ["description": task.description]))
                                        Text(DashboardLabels.text(task.status, domain: .task, language: language)).foregroundStyle(task.status == "running" ? .green : .secondary)
                                        Text(DashboardLabels.text(task.engineMode ?? "idle", domain: .engine, language: language)).foregroundStyle(.secondary)
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
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    var body: some View { Text(s(.dashboardUIDataWaiting)).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 70) }
}
struct DashboardTimestamp: View {
    let value: String
    var body: some View {
        if let date = DashboardFormat.date(value) {
            Text(date, style: .relative).font(.caption2).foregroundStyle(.secondary).help(value)
        } else { Text(value).font(.caption2).foregroundStyle(.secondary) }
    }
}
