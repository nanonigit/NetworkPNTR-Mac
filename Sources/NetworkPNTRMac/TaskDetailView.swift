import NetworkPNTRCore
import SwiftUI

@MainActor struct TaskDetailView: View {
    let model: TaskScreenModel
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let selectedID = model.store.selectedID {
                    if model.store.detail.isLoading { ProgressView().controlSize(.small) }
                    if let failure = model.store.detail.failure { Text(failure.text(language: language)).foregroundStyle(.red) }
                    if model.store.detail.isStale, model.store.detail.value != nil { Text(s(.taskUIStale)).font(.caption).foregroundStyle(.secondary) }
                    if let task = model.store.detail.value, task.id == selectedID {
                        Text(task.name.isEmpty ? AppStrings.formatted(.taskUIUnnamed, language: language, values: ["id": task.id]) : task.name).font(.title2.bold())
                        Text(task.id).font(.caption.monospaced()).textSelection(.enabled)
                        Text(DashboardLabels.text(task.status, domain: .task, language: language)).foregroundStyle(.secondary)
                        if model.store.activeID == task.id { Label(s(.taskUIActive), systemImage: "bolt.fill") }
                        if task.queued { Label(s(.taskUIQueued), systemImage: "clock") }
                        actions(task)
                        Divider()
                        field(.taskUIDescription, task.description)
                        field(.taskUIGoal, task.goal)
                        field(.taskUICategory, task.categoryName?.isEmpty == false ? task.categoryName! : s(.taskUIUncategorized))
                        field(.taskUICreated, date(task.createdUnix))
                        field(.taskUICompleted, date(task.completedUnix))
                        if let summary = model.store.list.value?.first(where: { $0.id == task.id }) {
                            field(.taskUIGoals, "\(summary.goalsMet)/\(summary.goalsTotal)")
                            field(.taskUITokens, TaskPresentation.tokens(summary))
                            Text(AppStrings.formatted(.taskUITokenBreakdown, language: language, values: ["input": String(summary.tokens.inputTokens), "read": String(summary.tokens.cacheReadTokens), "write": String(summary.tokens.cacheWriteTokens), "output": String(summary.tokens.outputTokens)])).font(.caption).textSelection(.enabled)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(s(.taskUIFindings)).font(.headline)
                                ForEach([("critical", summary.findings.critical), ("high", summary.findings.high), ("medium", summary.findings.medium), ("low", summary.findings.low)], id: \.0) { severity, count in
                                    LabeledContent(DashboardLabels.text(severity, domain: .severity, language: language), value: String(count))
                                }
                            }
                        }
                    }
                } else { ContentUnavailableView(s(.taskUISelect), systemImage: "sidebar.right") }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func date(_ seconds: Int64) -> String {
        guard seconds > 0, seconds <= 253_402_300_799 else { return "—" }
        return Date(timeIntervalSince1970: Double(seconds)).formatted(.dateTime.year().month().day().hour().minute().locale(locale))
    }
    private func field(_ label: AppStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(s(label)).font(.headline); Text(value.isEmpty ? "—" : value).textSelection(.enabled) }
    }
    private func actions(_ task: TaskRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(s(.taskUIRename)) { _ = model.beginRename(task) }
                Button(task.pinned ? s(.taskUIUnpin) : s(.taskUIPin)) { Task { await model.togglePin(task) } }
            }
            HStack {
                if let action = TaskPresentation.controlAction(task.status) {
                    Button(action == .pause ? s(.taskUIPause) : s(.taskUIResume)) { Task { await model.control(task) } }
                }
                if model.archiveActions != nil {
                    Button(s(.taskArchiveUIArchive),systemImage:"archivebox") { _ = model.beginArchive(task) }.disabled(!TaskArchiveSemantics.canArchive(task))
                }
                Button(s(.taskUIDelete), role: .destructive) { _ = model.beginDelete(task) }
            }
        }.disabled(model.busy)
    }
}
