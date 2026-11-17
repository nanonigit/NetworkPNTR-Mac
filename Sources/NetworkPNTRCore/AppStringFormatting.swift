extension AppStrings {
    /// Substitutes only tokens in the original catalog template, never in argument text.
    public static func formatted(_ key: AppStringKey, language: AppLanguage, values: [String: String]) -> String {
        render(template: text(key, language: language), values: values)
    }
    static func render(template: String, values: [String: String]) -> String {
        var result = ""
        var cursor = template.startIndex
        while let opening = template[cursor...].firstIndex(of: "{") {
            result += template[cursor..<opening]
            guard let closing = template[opening...].firstIndex(of: "}") else {
                result += template[opening...]; return result
            }
            let name = String(template[template.index(after: opening)..<closing])
            result += values[name] ?? String(template[opening...closing])
            cursor = template.index(after: closing)
        }
        result += template[cursor...]
        return result
    }
}
