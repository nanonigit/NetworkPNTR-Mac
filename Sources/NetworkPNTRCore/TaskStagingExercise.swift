import Foundation

public struct TaskStagingExerciseReport: Codable, Equatable, Sendable {
    public struct Record: Codable, Equatable, Sendable {
        public let name: String
        public let path: String
        public let size: Int64
        public let sha256: String
    }
    public let records: [Record]
    public let englishManifest: String
    public let japaneseManifest: String
    public let originalFilesPreserved: Bool
}

/// Finite synthetic contract exercise, never a task/agent operation or arbitrary host download.
@MainActor public enum TaskStagingExercise {
    public static let inputNames = ["fixture.bin", "empty.txt", "fixture.bin", "日本-e\u{301}.txt"]
    public static let firstNames = ["fixture.bin", "empty.txt", "fixture-1.bin", "日本-e\u{301}.txt"]
    public static let repeatNames = ["fixture-2.bin", "empty-1.txt", "fixture-3.bin", "日本-e\u{301}-1.txt"]
    public static let contents = [Data((0..<70001).map { UInt8($0 % 256) }), Data(), Data("second synthetic attachment\n".utf8), Data((0..<1280).map { UInt8($0 % 251) })]
    public static func run(files: [URL], draftID: UUID, client: any BackendJSONTransport, uploader: any TaskStagingUploading) async throws -> TaskStagingExerciseReport {
        try Task.checkCancellation()
        guard files.count == inputNames.count, zip(files,inputNames).allSatisfy({ $0.isFileURL && $0.lastPathComponent.utf8.elementsEqual($1.utf8) }) else { throw failure() }
        var batches: [[TaskStagedAttachment]] = [], records: [TaskStagingExerciseReport.Record] = []
        for names in [firstNames,repeatNames] {
            try Task.checkCancellation()
            let attachments = try await uploader.uploadTaskStaging(draftID: draftID, files: files, progress: nil)
            try Task.checkCancellation()
            guard attachments.count == contents.count else { throw failure() }
            for index in names.indices {
                guard attachments[index].draftID == draftID, attachments[index].name.utf8.elementsEqual(names[index].utf8),
                      attachments[index].size == Int64(contents[index].count) else { throw failure() }
            }
            records += try await verify(attachments, draftID: draftID, client: client)
            batches.append(attachments)
        }
        // Repeat has finished; prove the original four versions were not clobbered.
        _ = try await verify(batches[0], draftID: draftID, client: client)
        func manifest(_ language: AppLanguage) -> String {
            let result = batches.reduce("Task draft fixture") { TaskUploadManifest.appending(to: $0, attachments: $1, language: language) }
            return result.replacingOccurrences(of: "/state/app/data/drafts/" + draftID.uuidString.lowercased() + "/uploads/", with: "<draft>/uploads/")
        }
        return .init(records: records, englishManifest: manifest(.english), japaneseManifest: manifest(.japanese), originalFilesPreserved: true)
    }
    private static func verify(_ attachments: [TaskStagedAttachment], draftID: UUID, client: any BackendJSONTransport) async throws -> [TaskStagingExerciseReport.Record] {
        var records: [TaskStagingExerciseReport.Record] = []
        for (attachment, expected) in zip(attachments,contents) {
            try Task.checkCancellation()
            var query = URLComponents()
            query.queryItems = [URLQueryItem(name: "path", value: "drafts/" + draftID.uuidString.lowercased() + "/" + attachment.path)]
            guard let encoded = query.percentEncodedQuery else { throw failure() }
            let response = try await client.send(method: "GET", path: "/api/workspace/download?" + encoded, body: nil, bearer: nil)
            try Task.checkCancellation()
            guard response.status == 200, response.body == expected else { throw failure() }
            records.append(.init(name: attachment.name, path: attachment.path, size: attachment.size, sha256: ArtifactIntegrity.sha256(response.body)))
        }
        return records
    }
    private static func failure() -> RuntimeError { .integrity("task staging exercise contract") }
}
