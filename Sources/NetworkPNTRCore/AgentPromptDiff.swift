public enum AgentPromptDiff {
    public struct Line: Sendable {
        public enum Kind: Sendable { case unchanged, removed, added }
        public let kind: Kind
        public let text: String
    }

    /// Match the pinned browser's LCS and tie-breaking within a fixed memory budget.
    public static func compare(older: String, current: String) -> [Line]? {
        let oldLines = split(older)
        let newLines = split(current)
        let rows = oldLines.count + 1
        let columns = newLines.count + 1
        guard rows <= 1_000_000 / columns, rows + columns <= 20_000 else { return nil }

        // Compare interned UTF-8 line IDs to preserve byte identity without rehashing in the matrix.
        var ids: [ArraySlice<UInt8>: Int] = [:]
        func intern(_ lines: [ArraySlice<UInt8>]) -> [Int] {
            lines.map { line in
                if let known = ids[line] { return known }
                let id = ids.count
                ids[line] = id
                return id
            }
        }
        let a = intern(oldLines)
        let b = intern(newLines)
        var matrix = [Int32](repeating: 0, count: rows * columns)
        for i in 1..<rows {
            for j in 1..<columns {
                let index = i * columns + j
                matrix[index] = a[i - 1] == b[j - 1]
                    ? matrix[index - columns - 1] + 1
                    : max(matrix[index - columns], matrix[index - 1])
            }
        }

        var result: [Line] = []
        var i = a.count
        var j = b.count
        while i > 0 || j > 0 {
            if i > 0, j > 0, a[i - 1] == b[j - 1] {
                result.append(Line(kind: .unchanged, text: String(decoding: oldLines[i - 1], as: UTF8.self)))
                i -= 1
                j -= 1
            } else if j > 0 && (i == 0 || matrix[i * columns + j - 1] >= matrix[(i - 1) * columns + j]) {
                result.append(Line(kind: .added, text: String(decoding: newLines[j - 1], as: UTF8.self)))
                j -= 1
            } else {
                result.append(Line(kind: .removed, text: String(decoding: oldLines[i - 1], as: UTF8.self)))
                i -= 1
            }
        }
        result.reverse()
        return result
    }

    private static func split(_ text: String) -> [ArraySlice<UInt8>] {
        let bytes = Array(text.utf8)
        return bytes.isEmpty ? [bytes[...]] : bytes.split(separator: 10, maxSplits: 19_999, omittingEmptySubsequences: false)
    }
}
