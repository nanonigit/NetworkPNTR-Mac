#if DEBUG
import ArtexCore
import Foundation

/// Uses the production model with an automated chooser, never claims native panel acceptance.
@MainActor enum ProductionBodyModelProbe {
    @MainActor private final class Chooser: EvidenceDestinationChoosing {
        let destination: URL
        init(_ destination: URL) { self.destination = destination }
        func choose(suggestedFilename: String) async -> URL? { destination }
        func cancel() { }
    }
    @MainActor private final class HeldReceipt {
        var receipt: EvidenceExportReceipt?
        var continuation: CheckedContinuation<Void, Never>?
        var holding: Bool { continuation != nil }
        func stage(_ manifest: TrafficBlobDownload, destination: EvidenceExportDestination, session: AuthenticationSession) async throws -> EvidenceExportReceipt {
            receipt = try await session.authenticatedTrafficBlobExport(manifest, destination: destination)
            await withCheckedContinuation { continuation = $0 }
            guard let receipt else { throw failure() }
            self.receipt = nil
            return receipt
        }
        func release() { let pending = continuation; continuation = nil; pending?.resume() }
    }
    static func requireAvailable(_ controller: VMController) throws -> UUID {
        guard controller.hasMachine, let generation = controller.trafficBlobExportGeneration else { throw failure() }
        return generation
    }
    private static func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while !condition() {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw RuntimeError.timeout("production body model") }
            try await Task.sleep(for: .milliseconds(1))
        }
    }
    static func exercise(session: AuthenticationSession, api: any BackendJSONTransport, row: CapturedTrafficExchange,
                         directory: URL, controller: VMController) async throws -> [String: Any] {
        let generation = try requireAvailable(controller)
        guard let authentication = session.exportSessionGeneration else { throw failure() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let expected = try CapturedProbeContract.bytes(4, side: .response), hash = ArtifactIntegrity.sha256(expected)
        let service = TrafficService(client: api), retirement = TrafficBodyExportRetirement(), held = HeldReceipt()
        var models: [TrafficBodyExportModel] = []
        func make(exporter: @escaping TrafficBodyExporter) -> TrafficBodyExportModel {
            let scope = TrafficBodyExportScope(presentation: UUID(), storeOwner: UUID(), detailRevision: UUID(), trafficID: row.id)
            return TrafficBodyExportModel(scope: scope, isCurrent: { candidate, side in candidate == scope && side == .response }, available: {
                controller.trafficBlobExportGeneration == generation && session.exportSessionGeneration == authentication
            }, metadata: { id, side in
                let manifest = try await service.blobDownload(id: id, side: side)
                try SourceBlobProbe.validateManifest(manifest, row: row)
                return manifest
            }, exporter: exporter)
        }
        do {
            let model = make(exporter: session.authenticatedTrafficBlobExport); models.append(model)
            let original = directory.appendingPathComponent("original.bin")
            guard model.start(.response, owner: model.id, chooser: Chooser(original)) else { throw failure() }
            try await wait { !model.isExporting }
            guard model.failure == nil, let saved = model.saved, saved.byteCount == expected.count,
                  saved.sha256 == hash, saved.stagingCleanupComplete, saved.directorySynced else { throw failure() }
            _ = try EvidenceProbeFile.verify(original, body: "production-model", expected: .init(size: Int64(expected.count), sha256: hash))
            guard try Data(contentsOf: original) == expected else { throw failure() }
            retirement.retain(model)
            let late = make { manifest, destination in try await held.stage(manifest, destination: destination, session: session) }; models.append(late)
            let forbidden = directory.appendingPathComponent("must-not-publish.bin")
            guard late.start(.response, owner: late.id, chooser: Chooser(forbidden)) else { throw failure() }
            try await wait { held.holding || !late.isExporting }
            guard held.holding, held.receipt?.result.byteCount == Int64(expected.count),
                  !EvidenceProbeFile.stagingAbsent(directory), !FileManager.default.fileExists(atPath: forbidden.path) else { throw failure() }
            retirement.retain(late)
            guard !late.isActive, retirement.pendingCount == 1 else { throw failure() }
            held.release()
            try await wait { !late.isExporting && retirement.pendingCount == 0 }
            guard late.saved == nil, retirement.notices.isEmpty, EvidenceProbeFile.stagingAbsent(directory),
                  try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["original.bin"],
                  try requireAvailable(controller) == generation, session.exportSessionGeneration == authentication else { throw failure() }
            return ["productionModelShared": true, "bytes": expected.count, "sha256": hash,
                    "fullByteEqual": true, "lateVerifiedReceiptRetired": true, "noPublicationAfterRetirement": true,
                    "stagingAbsent": true, "retirementDrained": true, "generationsUnchanged": true,
                    "automatedChooser": true, "nativePanelAcceptance": false, "nativeUIAcceptance": false]
        } catch {
            let original = error
            for model in models { retirement.retain(model) }
            held.release()
            let draining = Task { @MainActor in
                try await wait { models.allSatisfy { !$0.isExporting } && retirement.pendingCount == 0 }
            }
            try await draining.value
            throw original
        }
    }
    private static func failure() -> RuntimeError { .integrity("production body model VM proof") }
}
#endif
