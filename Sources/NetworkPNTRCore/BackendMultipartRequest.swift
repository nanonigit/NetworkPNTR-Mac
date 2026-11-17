import Foundation

public enum BackendMultipartRequest {
    /// A dedicated route, not a generic host/URL/header upload facility.
    public static func header(conversationID: Int64, plan: ChatMultipartPlan, bearer: String) throws -> Data {
        guard conversationID > 0 else { throw ChatUploadBodyError.invalidFile }
        return try header(path: "/api/chat/upload?scope=session&id=conv-\(conversationID)", plan: plan, bearer: bearer)
    }
    public static func stagingHeader(draftID: UUID, plan: ChatMultipartPlan, bearer: String) throws -> Data {
        try header(path: "/api/chat/upload?scope=staging&id=" + draftID.uuidString.lowercased(), plan: plan, bearer: bearer)
    }
    private static func header(path: String, plan: ChatMultipartPlan, bearer: String) throws -> Data {
        guard !bearer.isEmpty, bearer.utf8.count <= 8192,
              bearer.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,46,95,126].contains($0) }) else {
            throw RuntimeError.integrity("authenticated attachment request")
        }
        return Data(("POST \(path) HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\nAccept: application/json\r\nContent-Type: \(plan.contentType)\r\nContent-Length: \(plan.contentLength)\r\nAuthorization: Bearer \(bearer)\r\n\r\n").utf8)
    }
}
