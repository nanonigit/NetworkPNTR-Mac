import Foundation

enum ToolRunPresentation {
    static func input(_ raw: String) -> String {
        guard let value = try? JSONSerialization.jsonObject(with: Data(raw.utf8), options: .fragmentsAllowed) else {
            return raw
        }
        if let fields = value as? [String: Any], let command = fields["command"] as? String {
            return command
        }
        guard let pretty = try? JSONSerialization.data(withJSONObject: value, options: [
            .prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed
        ]) else { return raw }
        return String(decoding: pretty, as: UTF8.self)
    }

    static func preview(_ raw: String) -> String {
        let input = input(raw)
        let firstLine = input.prefix { !$0.isNewline }
        guard firstLine.count > 80 else { return String(firstLine) }
        return String(firstLine.prefix(80)) + "…"
    }
}
