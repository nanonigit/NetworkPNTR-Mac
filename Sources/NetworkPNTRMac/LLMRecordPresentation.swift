import Foundation

enum LLMRecordPresentation {
    static func jsonBody(_ body: String?) -> String? {
        guard let body, !body.isEmpty else { return body }
        let bytes = Array(body.utf8)
        guard !bytes.starts(with: [0xef, 0xbb, 0xbf]),
              (try? JSONSerialization.jsonObject(with: Data(bytes), options: .fragmentsAllowed)) != nil else {
            return body
        }

        // Change whitespace only. Parsing and re-encoding can round numbers or discard duplicate keys.
        let outputLimit = 4 * 1024 * 1024
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var depth = 0
        var previous: UInt8?
        var insideString = false
        var escaped = false

        func appendLineBreak() -> Bool {
            let indentation = depth * 2
            guard output.count + indentation + 1 <= outputLimit else { return false }
            output.append(0x0a)
            output.append(contentsOf: repeatElement(0x20, count: indentation))
            return true
        }

        for byte in bytes {
            guard output.count < outputLimit else { return body }
            if insideString {
                output.append(byte)
                if escaped { escaped = false }
                else if byte == 0x5c { escaped = true }
                else if byte == 0x22 { insideString = false }
                continue
            }
            if byte == 0x20 || byte == 0x09 || byte == 0x0a || byte == 0x0d { continue }
            let followsOpening = previous == 0x7b || previous == 0x5b
            switch byte {
            case 0x7d, 0x5d: // } ]
                guard depth > 0, previous != 0x2c else { return body }
                depth -= 1
                if !followsOpening, !appendLineBreak() { return body }
                output.append(byte)
            default:
                if (followsOpening || previous == 0x2c), !appendLineBreak() { return body }
                if byte == 0x7b || byte == 0x5b { depth += 1 }
                if byte == 0x22 { insideString = true }
                output.append(byte)
                if byte == 0x3a { output.append(0x20) }
            }
            previous = byte
        }
        guard output.count <= outputLimit else { return body }
        return String(decoding: output, as: UTF8.self)
    }
}
