import Foundation

enum ToolRunPresentation {
    private struct CommandInput: Decodable { let command: String }

    static func input(_ raw: String) -> String {
        let data = Data(raw.utf8)
        if let input = try? JSONDecoder().decode(CommandInput.self, from: data) {
            return input.command
        }
        // JSONSerialization can strip a BOM at the start of a JSON string value.
        guard !raw.contains("\u{FEFF}"), raw.range(of: #"\uFEFF"#, options: .caseInsensitive) == nil,
              let value = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else {
            return raw
        }
        guard let pretty = try? JSONSerialization.data(withJSONObject: value, options: [
            .prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed
        ]) else { return raw }
        return String(decoding: pretty, as: UTF8.self)
    }

    static func pageRange(page: Int64, size: Int, count: Int) -> (first: Decimal, last: Decimal) {
        guard count > 0 else { return (0, 0) }
        let offset = Decimal(page) * Decimal(size)
        return (offset + 1, offset + Decimal(count))
    }

    static func share(count: Int64, total: Decimal) -> Decimal {
        total > 0 ? Decimal(count) / total : 0
    }

    static func preview(_ raw: String) -> String {
        let input = input(raw)
        let firstLine = input.prefix { !$0.isNewline }
        guard firstLine.count > 80 else { return String(firstLine) }
        return String(firstLine.prefix(80)) + "…"
    }
}
