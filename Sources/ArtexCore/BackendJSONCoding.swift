import Foundation

public enum BackendJSONCoding {
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            if type == TaskArchiveRecord.self || type == TaskArchivePage.self { return try TaskArchiveWire.decode(type,from:data) }
            return try decoder.decode(type, from: data)
        }
        catch { throw BackendAPIError.invalidResponse }
    }
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(value)
    }
    static func numericID(_ value: String) throws -> Int64 {
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
              let id = Int64(value), id > 0 else { throw BackendAPIError.invalidResponse }
        return id
    }
}
