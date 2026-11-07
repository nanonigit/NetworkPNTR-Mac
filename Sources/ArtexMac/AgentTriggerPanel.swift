import ArtexCore
import SwiftUI

@MainActor struct AgentTriggerPanel: View {
    let agent: AgentCatalogEntry
    let service: AgentCatalogService
    @Binding var busy: Bool
    @Binding var editing: Bool

    @Environment(\.locale) private var locale
    @State private var rows: [AgentTrigger] = []
    @State private var savedPolicy: AgentTriggerPolicy?
    @State private var policy = AgentTriggerPolicy(runMode: .serial, mergeMode: .all, maxParallel: 5)
    @State private var tools: [String] = []
    @State private var rule = AgentTriggerRule()
    @State private var editingID: Int64?
    @State private var removalID: Int64?
    @State private var failure: AppErrorMessage?

    private var loaded: Bool { savedPolicy != nil && failure == nil }
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(s(.agentTriggerHelp)).foregroundStyle(.secondary)
            if let failure {
                Text(failure.text(language: language)).foregroundStyle(.red)
                Button(s(.authRetry)) { Task { await load() } }.disabled(busy)
                if editing { Button(s(.chatCancel)) { editing = false }.disabled(busy) }
            }
            if busy { ProgressView().controlSize(.small) }
            if loaded {
                policyPanel.disabled(busy || editing)
                if editing {
                    rulePanel.disabled(busy)
                } else {
                    Button(s(.agentTriggerAdd), systemImage: "plus") { edit(nil) }.disabled(busy)
                    if rows.isEmpty { Text(s(.agentTriggerEmpty)).foregroundStyle(.secondary) }
                    ForEach(rows) { row in ruleRow(row).disabled(busy) }
                }
            }
        }
        .task { await load() }
        .confirmationDialog(s(.agentTriggerDeleteQuestion), isPresented: Binding(
            get: { removalID != nil }, set: { if !$0 { removalID = nil } }
        ), titleVisibility: .visible, presenting: removalID) { id in
            Button(s(.agentTriggerDelete), role: .destructive) {
                removalID = nil
                Task { await perform { rows = try await service.removeTrigger(for: agent, id: id) } }
            }
            Button(s(.chatCancel), role: .cancel) { removalID = nil }
        }
    }

    private var policyPanel: some View {
        GroupBox(s(.agentTriggerPolicy)) {
            VStack(alignment: .leading, spacing: 8) {
                Picker(s(.agentTriggerRun), selection: $policy.triggerRunMode) {
                    Text(s(.agentTriggerSerial)).tag(AgentTriggerPolicy.RunMode.serial)
                    Text(s(.agentTriggerParallel)).tag(AgentTriggerPolicy.RunMode.parallel)
                }
                if policy.triggerRunMode == .serial {
                    Picker(s(.agentTriggerMerge), selection: $policy.triggerMergeMode) {
                        Text(s(.agentTriggerByTask)).tag(AgentTriggerPolicy.MergeMode.byTask)
                        Text(s(.agentTriggerMergeAll)).tag(AgentTriggerPolicy.MergeMode.all)
                        Text(s(.agentTriggerMergeNone)).tag(AgentTriggerPolicy.MergeMode.none)
                    }
                } else {
                    TextField(s(.agentTriggerLimit), value: $policy.triggerMaxParallel, format: .number)
                }
                Button(s(.agentTriggerSavePolicy)) {
                    let desired = policy
                    Task { await perform { savedPolicy = try await service.saveTriggerPolicy(for: agent, policy: desired) } }
                }
                .disabled(!policy.isValid || policy == savedPolicy)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var rulePanel: some View {
        GroupBox(s(editingID == nil ? .agentTriggerAdd : .agentTriggerEdit)) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(s(.agentTriggerEnabled), isOn: $rule.enabled)
                condition(.agentTriggerSchedule, on: Binding(
                    get: { rule.intervalSec != 0 }, set: { rule.intervalSec = $0 ? 60 : 0 }
                ), message: $rule.intervalMessage)
                if rule.intervalSec != 0 {
                    TextField(s(.agentTriggerSeconds), value: $rule.intervalSec, format: .number)
                }
                condition(.agentTriggerFinding, on: $rule.onFinding, message: $rule.findingMessage)
                condition(.agentTriggerGoal, on: $rule.onGoalMet, message: $rule.goalMessage)
                condition(.agentTriggerTimeout, on: $rule.onTaskTimeout, message: $rule.taskTimeoutMessage)
                condition(.agentTriggerTask, on: $rule.onTaskCreate, message: $rule.taskCreateMessage)
                condition(.agentTriggerTool, on: $rule.onToolCall, message: $rule.toolCallMessage)
                if rule.onToolCall {
                    Text(s(.agentTriggerTools)).font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(Set(tools + (rule.toolNames ?? []))).sorted(), id: \.self) { tool in
                        Toggle(tool, isOn: Binding(
                            get: { rule.toolNames?.contains(tool) ?? false },
                            set: { included in
                                var selected = rule.toolNames ?? []
                                if included { selected.append(tool) }
                                else { selected.removeAll { $0 == tool } }
                                rule.toolNames = selected
                            }
                        )).toggleStyle(.checkbox)
                    }
                }
                HStack {
                    Button(s(.chatCancel)) { editing = false }
                    Button(s(.agentTriggerSave)) { saveRule() }.buttonStyle(.borderedProminent).disabled(!rule.isValid)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func condition(_ title: AppStringKey, on: Binding<Bool>, message: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(s(title), isOn: on).toggleStyle(.checkbox)
            if on.wrappedValue {
                TextField(s(.agentTriggerMessage), text: message, axis: .vertical)
                    .accessibilityLabel(s(title) + " · " + s(.agentTriggerMessage))
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func ruleRow(_ row: AgentTrigger) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summary(row.rule)).font(.headline)
            if row.rule.intervalSec > 0 {
                LabeledContent(s(.agentTriggerSeconds), value: row.rule.intervalSec.formatted())
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let lastFire = row.lastFire {
                LabeledContent(s(.agentTriggerLastFire), value: lastFire).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(s(row.rule.enabled ? .agentTriggerDisable : .agentTriggerEnable)) {
                    Task {
                        await perform {
                            rows = try await service.setTriggerEnabled(for: agent, id: row.id, enabled: !row.rule.enabled)
                        }
                    }
                }
                Button(s(.agentTriggerEdit)) { edit(row) }
                Button(s(.agentTriggerDelete), role: .destructive) { removalID = row.id }
            }
        }
        .accessibilityIdentifier("agent-trigger-rule-\(row.id)")
    }

    private func summary(_ rule: AgentTriggerRule) -> String {
        let conditions: [(Bool, AppStringKey)] = [
            (rule.intervalSec > 0, .agentTriggerSchedule), (rule.onFinding, .agentTriggerFinding),
            (rule.onGoalMet, .agentTriggerGoal), (rule.onTaskTimeout, .agentTriggerTimeout),
            (rule.onTaskCreate, .agentTriggerTask), (rule.onToolCall, .agentTriggerTool)
        ]
        return ([s(rule.enabled ? .agentTriggerEnabled : .agentTriggerDisabled)] +
                conditions.filter(\.0).map { s($0.1) }).joined(separator: " · ")
    }

    private func edit(_ row: AgentTrigger?) {
        editingID = row?.id
        rule = row?.rule ?? AgentTriggerRule()
        editing = true
    }

    private func saveRule() {
        let draft = rule
        let id = editingID
        Task {
            await perform {
                if let id { rows = try await service.updateTrigger(for: agent, id: id, rule: draft) }
                else { rows = try await service.createTrigger(for: agent, rule: draft) }
                editing = false
            }
        }
    }

    private func load() async {
        await perform {
            let fetched = try await service.triggers(for: agent)
            let configuration = try await service.triggerPolicy(for: agent)
            let names = try await service.triggerToolNames()
            rows = fetched
            savedPolicy = configuration
            policy = configuration
            tools = names
            // A failed save may have committed. Reload before starting another edit.
            editing = false
        }
    }

    private func perform(_ operation: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        failure = nil
        defer { busy = false }
        do { try await operation() }
        catch { if !Task.isCancelled { failure = AppErrorMessage(error) } }
    }
}
