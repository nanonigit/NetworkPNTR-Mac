import Foundation

@MainActor public protocol BackendEvidenceDownloadTransport {
    func stageEvidence(_ manifest: FindingEvidenceDownload, destination: EvidenceExportDestination, bearer: String) async throws -> EvidenceExportReceipt
}

/// A single-use staging capability. Publication revalidates transport, authentication and UI owners.
@MainActor public final class EvidenceExportReceipt {
    public let result: BackendDownloadResult
    private var file: VerifiedEvidenceFile?
    private var consumed = false
    private var validators: [@MainActor () throws -> Void]

    init(response: EvidenceDownloadResponse, validate: @escaping @MainActor () throws -> Void = {}) {
        result = response.result; file = response.file; validators = [validate]
    }
    func requireSuccess(_ manifest: FindingEvidenceDownload) throws {
        guard !consumed, file != nil, result.status == 200,
              result.byteCount == manifest.expectedSize, result.sha256 == manifest.expectedSHA256 else {
            throw EvidenceExportError.integrity
        }
        try validateOwnership()
    }
    func restrict(validate: @escaping @MainActor () throws -> Void) {
        validators.append(validate)
    }
    private func validateOwnership() throws {
        try Task.checkCancellation()
        for validate in validators { try validate() }
        try Task.checkCancellation()
    }
    public func commit(validate: @MainActor () throws -> Void = {}) throws -> SavedEvidenceFile {
        guard !consumed else { throw EvidenceExportError.integrity }
        consumed = true
        let staged = file; file = nil
        defer { validators.removeAll() }
        do {
            try Task.checkCancellation()
            guard result.status == 200, let staged else { throw EvidenceExportError.integrity }
            try validate()
            try validateOwnership()
            return try staged.commit()
        } catch {
            try staged?.discard()
            throw error
        }
    }
    public func discard() throws {
        consumed = true
        let staged = file; file = nil
        validators.removeAll()
        try staged?.discard()
    }
}
