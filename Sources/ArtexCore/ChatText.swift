import Foundation

/// ECMAScript whitespace used by the pinned browser composer and mention search.
public enum ChatText {
    public static func trim(_ input: String, end: Bool = true) -> String {
        func space(_ value: Unicode.Scalar) -> Bool {
            let n = value.value
            return (9...13).contains(n) || [32,0xA0,0x1680,0x2028,0x2029,0x202F,0x205F,0x3000,0xFEFF].contains(n) || (0x2000...0x200A).contains(n)
        }
        var values = input.unicodeScalars
        while let first = values.first, space(first) { values.removeFirst() }
        if end { while let last = values.last, space(last) { values.removeLast() } }
        return String(values)
    }
}
