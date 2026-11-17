import NetworkPNTRCore
import SwiftUI

struct LLMNumberField<Value: LosslessStringConvertible & Equatable>: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    let label: String
    @Binding var value: Value
    let valid: (Value) -> Bool
    let validity: (Bool) -> Void
    @State private var text: String
    init(_ label: String, value: Binding<Value>, valid: @escaping (Value) -> Bool, validity: @escaping (Bool) -> Void) {
        self.label = label; _value = value; self.valid = valid; self.validity = validity
        _text = State(initialValue: String(value.wrappedValue))
    }
    private var parsed: Value? {
        let raw = text.trimmingCharacters(in: .whitespaces)
        return Value(raw.isEmpty ? "0" : raw)
    }
    private var isValid: Bool { parsed.map(valid) ?? false }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: $text).labelsHidden()
            if !isValid { Text(s(.llmUIInvalidNumber)).font(.caption).foregroundStyle(.red) }
        }
        .onAppear { validity(isValid) }
        .onChange(of: text) { _, _ in
            if let parsed, valid(parsed), parsed != value { value = parsed }
            validity(isValid)
        }
        .onChange(of: value) { _, new in
            if parsed != new { text = String(new); validity(valid(new)) }
        }
    }
}

struct LLMRetryRuleFields: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    let title: String
    let detail: String
    @Binding var rule: LLMRetryRule
    let validity: (String, Bool) -> Void
    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 8) {
                Text(detail).font(.caption).foregroundStyle(.secondary)
                HStack {
                    LLMNumberField(s(.llmUIAttempts), value: $rule.attempts, valid: { (-1...20).contains($0) }) { validity("attempts", $0) }
                    LLMNumberField(s(.llmUIInterval), value: $rule.intervalMs, valid: { (0...3_600_000).contains($0) }) { validity("interval", $0) }
                }
                Text(s(.llmUIRetryDefaults)).font(.caption2).foregroundStyle(.secondary)
            }.padding(6)
        }
    }
}
