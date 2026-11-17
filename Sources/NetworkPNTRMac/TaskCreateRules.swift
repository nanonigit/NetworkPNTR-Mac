import NetworkPNTRCore
import SwiftUI

@MainActor struct TaskCreateRules: View {
    let model: TaskCreationModel
    let contextID: UUID
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    var body: some View {
        GroupBox(s(.taskCreateRules)) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(model.form.rules) { row in
                    TaskCreateRuleRow(model: model, contextID: contextID, ruleID: row.id)
                }
                Button(s(.taskCreateAddRule), systemImage: "plus") { model.addRule(contextID: contextID) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@MainActor private struct TaskCreateRuleRow: View {
    let model: TaskCreationModel
    let contextID: UUID
    let ruleID: UUID
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    private func field<Value>(_ key: WritableKeyPath<TaskInterceptRuleDraft, Value>, _ fallback: Value) -> Binding<Value> {
        TaskCreationBindings.rule(model: model, contextID: contextID, ruleID: ruleID, key: key, fallback: fallback)
    }
    var body: some View {
        TaskRuleEditorRow(enabled:field(\.enabled,false),action:field(\.action,.block),kind:field(\.kind,.exactDomain),pattern:field(\.pattern,""),note:field(\.note,"")) { model.removeRule(id:ruleID,contextID:contextID) }
    }
}

@MainActor struct TaskRuleEditorRow: View {
    @Binding var enabled: Bool
    @Binding var action: TaskInterceptRuleDraft.Action
    @Binding var kind: TaskInterceptRuleDraft.Kind
    @Binding var pattern: String
    @Binding var note: String
    let onRemove: () -> Void
    @Environment(\.locale) private var locale
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key,language:.preferred(in:[locale.identifier])) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(s(.taskCreateRuleEnabled), isOn: $enabled)
                Picker(s(.taskCreateRuleAction), selection: $action) {
                    Text(s(.taskCreateBlock)).tag(TaskInterceptRuleDraft.Action.block)
                    Text(s(.taskCreateAllow)).tag(TaskInterceptRuleDraft.Action.allow)
                }
                Button(s(.taskCreateRemoveRule), systemImage: "minus.circle", role: .destructive) { onRemove() }.labelStyle(.iconOnly)
            }
            Picker(s(.taskCreateRuleKind), selection: $kind) {
                ForEach(TaskInterceptRuleDraft.Kind.allCases, id: \.self) { kind in Text(s(kindKey(kind))).tag(kind) }
            }
            TextField(s(.taskCreatePattern), text: $pattern).textFieldStyle(.roundedBorder)
            TextField(s(.taskCreateNote), text: $note).textFieldStyle(.roundedBorder)
            Divider()
        }
    }
    private func kindKey(_ kind: TaskInterceptRuleDraft.Kind) -> AppStringKey {
        switch kind {
        case .exactDomain: .taskCreateExactDomain
        case .exactIp: .taskCreateExactIp
        case .exactUrl: .taskCreateExactUrl
        case .fuzzyDomain: .taskCreateFuzzyDomain
        case .fuzzyIp: .taskCreateFuzzyIp
        case .fuzzyUrl: .taskCreateFuzzyUrl
        case .cidr: .taskCreateCidr
        }
    }
}
