#if DEBUG
import Foundation

enum NativeLocalSessionReport {
    static func publish(_ result: [String: Any], at destination: URL,
                        write: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) throws {
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try write(data, destination)
    }
}
#endif
