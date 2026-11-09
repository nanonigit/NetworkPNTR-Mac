import Foundation

public enum AssetDSLSuggestions {
    public struct Suggestion: Identifiable {
        public let label: String
        public let descriptionKey: AppStringKey
        public let replacement: Range<String.Index>
        public let insertion: String

        public var id: String { label }
    }

    private typealias Operator = (symbol: String, description: AppStringKey)

    private static let stringOperators: [Operator] = [
        ("=", .assetDSLOpFuzzy), ("==", .assetDSLOpExact), ("!=", .assetDSLOpExclude)
    ]
    private static let exactOperators = Array(stringOperators.dropFirst())
    private static let numericOperators: [Operator] = [
        ("==", .assetDSLOpEq), ("!=", .assetDSLOpNe), (">", .assetDSLOpGt),
        (">=", .assetDSLOpGte), ("<", .assetDSLOpLt), ("<=", .assetDSLOpLte)
    ]
    private static let equalityOperators: [Operator] = [("==", .assetDSLOpEq)]
    private static let fields: [(name: String, description: AppStringKey, operators: [Operator])] = [
        ("domain", .assetDSLFieldDomain, stringOperators),
        ("ip", .assetDSLFieldIp, stringOperators),
        ("url", .assetDSLFieldUrl, stringOperators),
        ("root_domain", .assetDSLFieldRootDomain, stringOperators),
        ("page_title", .assetDSLFieldPageTitle, stringOperators),
        ("icp", .assetDSLFieldIcp, stringOperators),
        ("service_name", .assetDSLFieldServiceName, stringOperators),
        ("app_name", .assetDSLFieldAppName, stringOperators),
        ("bundle_id", .assetDSLFieldBundleId, stringOperators),
        ("category", .assetDSLFieldCategory, stringOperators),
        ("app_icp", .assetDSLFieldAppIcp, stringOperators),
        ("method", .assetDSLFieldMethod, exactOperators),
        ("service_type", .assetDSLFieldServiceType, exactOperators),
        ("record_type", .assetDSLFieldRecordType, exactOperators),
        ("technology", .assetDSLFieldTechnology, stringOperators),
        ("port", .assetDSLFieldPort, numericOperators),
        ("status_code", .assetDSLFieldStatusCode, numericOperators),
        ("company_id", .assetDSLFieldCompanyId, equalityOperators),
        ("task_id", .assetDSLFieldTaskId, equalityOperators)
    ]
    private static let logic: [(label: String, description: AppStringKey)] = [
        ("AND", .assetDSLLogicAnd), ("OR", .assetDSLLogicOr)
    ]

    public static func items(in text: String, at cursor: String.Index) -> [Suggestion] {
        let before = text[..<cursor]
        let token = before.reversed().prefix { !$0.isWhitespace && $0 != "(" && $0 != ")" }
        let start = text.index(cursor, offsetBy: -token.count)
        let range = start..<cursor
        let prefix = text[range].lowercased()

        func item(_ label: String, _ description: AppStringKey, insertion: String? = nil) -> Suggestion {
            Suggestion(label: label, descriptionKey: description, replacement: range, insertion: insertion ?? label)
        }

        if let field = fields.first(where: { $0.name == prefix }) {
            return field.operators.map { item(field.name + $0.symbol, $0.description) }
        }

        let leading = before[..<start].trimmingCharacters(in: .whitespacesAndNewlines)
        let afterExpression = !leading.isEmpty && !leading.hasSuffix("(")
            && leading.range(of: #"\b(AND|OR)$"#, options: [.regularExpression, .caseInsensitive]) == nil
        let logicMatches = logic.filter { $0.label.lowercased().hasPrefix(prefix) }
        if afterExpression, !logicMatches.isEmpty {
            return logicMatches.map { item($0.label, $0.description, insertion: $0.label + " ") }
        }

        return fields.filter { $0.name.hasPrefix(prefix) }.map { item($0.name, $0.description) }
    }

    public static func apply(_ suggestion: Suggestion, to text: String) -> (text: String, caret: String.Index) {
        let before = String(text[..<suggestion.replacement.lowerBound]) + suggestion.insertion
        let updated = before + text[suggestion.replacement.upperBound...]
        let caret = String.Index(utf16Offset: before.utf16.count, in: updated)
        return (updated, caret)
    }
}
