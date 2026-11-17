import NetworkPNTRCore
import SwiftUI

@MainActor enum TaskCreationBindings {
    static func field<Value>(model: TaskCreationModel, contextID: UUID, key: WritableKeyPath<TaskCreationForm, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { model.context?.id == contextID ? model.form[keyPath: key] : fallback }, set: { model.update(key, value: $0, contextID: contextID) })
    }
    static func rule<Value>(model: TaskCreationModel, contextID: UUID, ruleID: UUID, key: WritableKeyPath<TaskInterceptRuleDraft, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { model.context?.id == contextID ? model.form.rules.first(where: { $0.id == ruleID })?.rule[keyPath: key] ?? fallback : fallback },
                set: { model.updateRule(id: ruleID, key: key, value: $0, contextID: contextID) })
    }
}
