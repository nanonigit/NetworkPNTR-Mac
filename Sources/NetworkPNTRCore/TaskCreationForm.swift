import Foundation

public struct TaskCreationRule: Identifiable, Sendable {
    public let id = UUID()
    public var rule: TaskInterceptRuleDraft
    public init(rule: TaskInterceptRuleDraft = .init(enabled: true, action: .block, kind: .exactDomain, pattern: "", note: "")) { self.rule = rule }
}
public struct TaskCreationForm: Sendable {
    public var draft = TaskCreateDraft()
    public var timeoutMinutes = ""
    public var heartbeatMinutes = "10"
    public var rules: [TaskCreationRule] = []
    public init() {}
    public mutating func apply(_ template: TaskTemplateOption) {
        draft.description = template.description; draft.goal = template.goal; draft.categoryId = template.categoryId
        rules = template.interceptRules.map { TaskCreationRule(rule: $0) }
    }
    public func payload() throws -> TaskCreateDraft {
        var result = draft
        result.timeoutSeconds = try Self.seconds(timeoutMinutes, minimum: 0, empty: 0)
        result.planHeartbeatSeconds = try Self.seconds(heartbeatMinutes, minimum: 10, empty: 10)
        result.interceptRules = rules.map(\.rule)
        _ = try result.encoded()
        return result
    }
    private static func seconds(_ raw: String, minimum: Int64, empty: Int64) throws -> Int64 {
        let value = ChatText.trim(raw)
        if value.isEmpty { return empty * 60 }
        let pattern = #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#
        guard value.range(of: pattern, options: .regularExpression) != nil,
              var minutes = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")), !minutes.isNaN else { throw TaskInputError.invalidCreation }
        var rounded = Decimal(); NSDecimalRound(&rounded, &minutes, 0, .down)
        rounded = max(Decimal(minimum), rounded)
        guard rounded <= Decimal(Int64.max / 60) else { throw TaskInputError.invalidCreation }
        return NSDecimalNumber(decimal: rounded).int64Value * 60
    }
}
