import Foundation

public struct ChatMentionActive: Equatable, Sendable {
    public let range: NSRange
    public let query: String
}
public struct ChatMentionSearchInput: Equatable, Sendable {
    public let kind: ChatMentionKind?
    public let query: String
    public let categories: [ChatMentionKind]
}
public struct ChatMentionEdit: Equatable, Sendable {
    public let text: String
    public let caret: Int
}
public struct ChatSelectedMention: Equatable, Sendable {
    public let token: String
    public let kind: ChatMentionKind
    public let id: String
    public let text: String
    public let range: NSRange
}

public enum ChatMentionEditing {
    private static func slice(_ units: [UInt16], _ range: Range<Int>) -> String { String(decoding: units[range], as: UTF16.self) }
    public static func active(in value: String, caret: Int, composing: Bool = false) -> ChatMentionActive? {
        let units = Array(value.utf16)
        guard !composing, caret >= 0, caret <= units.count else { return nil }
        if caret > 0, caret < units.count, (0xD800...0xDBFF).contains(units[caret - 1]), (0xDC00...0xDFFF).contains(units[caret]) { return nil }
        guard let start = units[..<caret].lastIndex(of: 64) else { return nil }
        if start > 0 {
            let previous = units[start - 1]
            if (48...57).contains(previous) || (65...90).contains(previous) || (97...122).contains(previous) || [95,46,43,47,45].contains(previous) { return nil }
        }
        let queryUnits = units[(start + 1)..<caret]
        guard queryUnits.count <= 220, !queryUnits.contains(where: { [91,93,13,10,64].contains($0) }) else { return nil }
        return ChatMentionActive(range: NSRange(location: start, length: caret - start), query: String(decoding: queryUnits, as: UTF16.self))
    }
    private static func trimJS(_ input: String, end: Bool = true) -> String {
        func space(_ value: Unicode.Scalar) -> Bool {
            let n = value.value
            return (9...13).contains(n) || [32,0xA0,0x1680,0x2028,0x2029,0x202F,0x205F,0x3000,0xFEFF].contains(n) || (0x2000...0x200A).contains(n)
        }
        var values = input.unicodeScalars
        while let first = values.first, space(first) { values.removeFirst() }
        if end { while let last = values.last, space(last) { values.removeLast() } }
        return String(values)
    }
    private static func alias(_ kind: ChatMentionKind) -> String {
        switch kind { case .endpoint: "api"; case .rootDomain: "domain"; default: kind.rawValue }
    }
    public static func search(_ input: String) -> ChatMentionSearchInput {
        let trimmed = trimJS(input, end: false)
        let text = trimmed.lowercased()
        for kind in ChatMentionKind.allCases {
            for alias in [kind.wireLabel.lowercased(), alias(kind)] {
                let nonLatin = alias.unicodeScalars.contains { !(97...122).contains($0.value) }
                if text == alias || text.hasPrefix(alias + " ") || (nonLatin && text.hasPrefix(alias)) {
                    return .init(kind: kind, query: trimJS(String(trimmed.dropFirst(alias.count))), categories: [])
                }
            }
        }
        return .init(kind: nil, query: trimJS(input), categories: ChatMentionKind.allCases.filter { $0.wireLabel.lowercased().hasPrefix(text) || alias($0).hasPrefix(text) })
    }
    public static func replace(in value: String, active expected: ChatMentionActive, with text: String) -> ChatMentionEdit? {
        let (end, overflow) = expected.range.location.addingReportingOverflow(expected.range.length)
        guard !overflow, active(in: value, caret: end) == expected else { return nil }
        let units = Array(value.utf16)
        let prefix = slice(units, 0..<expected.range.location)
        let suffix = slice(units, end..<units.count)
        return .init(text: prefix + text + suffix, caret: expected.range.location + text.utf16.count)
    }
    public static func selected(in value: String) -> [ChatSelectedMention] {
        guard let regex = try? NSRegularExpression(pattern: "@\\[(漏洞|资产|企业|接口|IP|应用|域名|子域名|服务)#([0-9]+)(?: ([^\\]\\r\\n]*))?\\]") else { return [] }
        let units = Array(value.utf16)
        func field(_ match: NSTextCheckingResult, _ index: Int) -> String {
            let range = match.range(at: index)
            return range.location == NSNotFound ? "" : slice(units, range.location..<(range.location + range.length))
        }
        return regex.matches(in: value, range: NSRange(location: 0, length: units.count)).compactMap { match in
            guard let kind = ChatMentionKind.allCases.first(where: { $0.wireLabel == field(match, 1) }) else { return nil }
            return .init(token: field(match, 0), kind: kind, id: field(match, 2), text: field(match, 3), range: match.range)
        }
    }
    public static func remove(_ target: ChatSelectedMention, from value: String) -> ChatMentionEdit? {
        guard selected(in: value).contains(target) else { return nil }
        let units = Array(value.utf16); let end = target.range.location + target.range.length
        return .init(text: slice(units, 0..<target.range.location) + slice(units, end..<units.count), caret: target.range.location)
    }
}
