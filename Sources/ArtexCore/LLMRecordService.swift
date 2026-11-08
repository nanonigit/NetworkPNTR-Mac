import Foundation

public struct LLMRecordFilter: Sendable {
    public let model: String
    public let session: String
    public let task: String

    public init(model: String = "", session: String = "", task: String = "") {
        self.model = model
        self.session = ChatText.trim(session)
        self.task = task
    }
}

public struct LLMRecord: Decodable, Identifiable, Sendable {
    public let id: Int64
    public let ts: String
    public let model: String
    public let profileName: String
    public let sessionId: String
    public let taskId: String
    public let worker: String
    public let latencyMs: Int64
    public let inputTokens: Int64
    public let outputTokens: Int64
    public let cacheRead: Int64
    public let cacheWrite: Int64
    public let status: String
    public let error: String?
}

public struct LLMRecordPage: Decodable, Sendable {
    public let records: [LLMRecord]
    public let total: Int64
}

public struct LLMRecordTask: Decodable, Sendable {
    public let taskId: String
    public let count: Int64
}

public struct LLMRecordDetail: Decodable, Sendable {
    public let record: LLMRecord
    public let requestBody: String?
    public let responseBody: String?
    public let rawRequest: String?
    public let rawResponse: String?

    private enum CodingKeys: String, CodingKey {
        case requestBody, responseBody, rawRequest, rawResponse
    }

    public init(from decoder: Decoder) throws {
        record = try LLMRecord(from: decoder)
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        requestBody = try fields.decodeIfPresent(String.self, forKey: .requestBody)
        responseBody = try fields.decodeIfPresent(String.self, forKey: .responseBody)
        rawRequest = try fields.decodeIfPresent(String.self, forKey: .rawRequest)
        rawResponse = try fields.decodeIfPresent(String.self, forKey: .rawResponse)
    }
}

public enum LLMRecordQueryError: Error, Sendable {
    case invalidQuery
}

@MainActor public final class LLMRecordService {
    public static let pageSizes = [25, 50, 100]
    private let client: any BackendJSONTransport
    private let route = "/api/llm/records"

    public init(client: any BackendJSONTransport) { self.client = client }

    public func list(filter: LLMRecordFilter = .init(), page: Int64 = 0, size: Int = 50) async throws -> LLMRecordPage {
        guard Self.pageSizes.contains(size), page >= 0, page <= Int64.max / Int64(size) else {
            throw LLMRecordQueryError.invalidQuery
        }
        let filters = [("model", filter.model), ("session", filter.session), ("task", filter.task)]
        guard filters.allSatisfy({ $0.1.utf8.count <= 8192 }) else { throw LLMRecordQueryError.invalidQuery }
        var query = URLComponents()
        query.queryItems = [URLQueryItem(name: "page", value: String(page)), .init(name: "size", value: String(size))]
            + filters.filter { !$0.1.isEmpty }.map { .init(name: $0.0, value: $0.1) }
        guard let encoded = query.percentEncodedQuery else { throw LLMRecordQueryError.invalidQuery }
        let result: LLMRecordPage = try await read(route + "?" + encoded.replacingOccurrences(of: "+", with: "%2B"))
        guard result.total >= 0, result.records.count <= size, result.records.allSatisfy({ $0.id > 0 }),
              Set(result.records.map(\.id)).count == result.records.count else {
            throw BackendAPIError.invalidResponse
        }
        return result
    }

    public func tasks() async throws -> [LLMRecordTask] {
        struct Reply: Decodable { let tasks: [LLMRecordTask]? }
        let result: Reply = try await read(route + "/tasks")
        let tasks = result.tasks ?? []
        guard tasks.allSatisfy({ !$0.taskId.isEmpty && $0.count > 0 }) else {
            throw BackendAPIError.invalidResponse
        }
        return tasks
    }

    public func detail(id: Int64) async throws -> LLMRecordDetail {
        guard id > 0 else { throw LLMRecordQueryError.invalidQuery }
        let result: LLMRecordDetail = try await read(route + "/" + String(id))
        guard result.record.id == id else { throw BackendAPIError.invalidResponse }
        return result
    }

    private func read<T: Decodable>(_ path: String) async throws -> T {
        try Task.checkCancellation()
        guard path.utf8.count <= 8192 else { throw LLMRecordQueryError.invalidQuery }
        let response = try await client.send(method: "GET", path: path, body: nil, bearer: nil)
        try Task.checkCancellation()
        guard (200..<300).contains(response.status) else { throw BackendAPIError.status(response.status) }
        guard response.status == 200, response.body.count <= 4 * 1024 * 1024 else {
            throw BackendAPIError.invalidResponse
        }
        return try BackendJSONCoding.decode(T.self, from: response.body)
    }
}
