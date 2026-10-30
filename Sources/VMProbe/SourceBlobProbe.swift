#if DEBUG
import ArtexCore
import Foundation

/// Fixed source-blob extension of the owned loopback experiment, not native UI acceptance.
@MainActor enum SourceBlobProbe {
    static func validateCandidate(_ metadata: [String: Any]) throws {
        guard metadata["architecture"] as? String == "arm64",
              metadata["sourceCommit"] as? String == "e75ae371ad777ffd1eecdd28d2781a6519b05591",
              metadata["bootMode"] as? String == "rootDisk", metadata["cpuCount"] as? Int == 1,
              metadata["networkDevices"] as? Int == 0, metadata["hostShares"] as? Int == 0,
              let capabilities = metadata["managedCapabilities"] as? [String],
              capabilities.contains("traffic-blob-metadata-v1"), capabilities.contains("regular-source-blob-stream-v1"),
              let managed = metadata["managedBackend"] as? [String: Any],
              managed["buildVersion"] as? String == "artex-mac-e75ae371-blob1",
              let digest = managed["binarySHA256"] as? String, digest.utf8.count == 64,
              digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              metadata["backendSHA256"] as? String == digest else { throw failure() }
    }
    static func validateManifest(_ manifest: TrafficBlobDownload, row: CapturedTrafficExchange) throws {
        let expected = try CapturedProbeContract.bytes(4, side: .response)
        guard try CapturedProbeContract.ordinal(row.url) == 4, manifest.identity == row.identity,
              manifest.side == .response, manifest.expectedSize == expected.count,
              row.responseLength == expected.count,
              manifest.expectedSHA256 == ArtifactIntegrity.sha256(expected) else { throw failure() }
    }
    @MainActor final class Result {
        private let session: AuthenticationSession
        private let authenticationWitness: @MainActor () throws -> Void
        private let manifest: TrafficBlobDownload
        private let row: CapturedTrafficExchange
        private let directory: URL
        private let saved: URL
        private var pending: EvidenceExportReceipt?
        private var stopped = false, rebooted = false
        fileprivate init(session: AuthenticationSession, authenticationWitness: @escaping @MainActor () throws -> Void, manifest: TrafficBlobDownload, row: CapturedTrafficExchange, directory: URL, saved: URL, pending: EvidenceExportReceipt) {
            self.session = session; self.authenticationWitness = authenticationWitness
            self.manifest = manifest; self.row = row; self.directory = directory; self.saved = saved; self.pending = pending
        }
        func discardPending() throws { let receipt = pending; pending = nil; try receipt?.discard() }
        func afterVMStop() throws {
            guard let receipt = pending else { throw failure() }
            defer { withExtendedLifetime(session) { } }
            try Task.checkCancellation()
            try authenticationWitness()
            do { _ = try receipt.commit(); throw failure() }
            catch is CancellationError {
                try Task.checkCancellation()
                try authenticationWitness()
            }
            try discardPending()
            guard !FileManager.default.fileExists(atPath: directory.appendingPathComponent("source-must-not-publish.bin").path),
                  try FileManager.default.contentsOfDirectory(atPath: directory.path).allSatisfy({ !$0.hasPrefix(".artex-evidence-") }) else { throw failure() }
            stopped = true
        }
        func verifyReboot(session: AuthenticationSession, api: any BackendJSONTransport) async throws {
            guard stopped else { throw failure() }
            let current = try await TrafficService(client: api).blobDownload(id: row.id, side: .response)
            try validateManifest(current, row: row)
            let expected = try CapturedProbeContract.bytes(4, side: .response)
            guard try Data(contentsOf: saved) == expected else { throw failure() }
            _ = try await save(session: session, manifest: current, directory: directory, name: "source-original-4-response-reboot.bin")
            rebooted = true
        }
        func requireComplete() throws { guard stopped, rebooted, pending == nil else { throw failure() } }
        var report: [String: Any] {
            ["ordinal": 4, "side": "response", "bytes": Int(manifest.expectedSize), "sha256": manifest.expectedSHA256,
             "literalManifestBound": true, "fullByteEqual": true, "badLengthRefused": true, "inlineRefused": true,
             "vmStopPublicationRejected": stopped, "rebootByteEqual": rebooted, "nativeUIAcceptance": false]
        }
    }
    static func exercise(session: AuthenticationSession, api: any BackendJSONTransport,
                         records: [CapturedTrafficExchange], directory: URL) async throws -> Result {
        guard records.count == 29 else { throw failure() }
        let authenticationWitness = try session.exportOwnershipWitness()
        let row = records[4], service = TrafficService(client: api)
        let manifest = try await service.blobDownload(id: row.id, side: .response)
        try validateManifest(manifest, row: row)
        for (id, side) in [(records[3].id, FindingEvidenceSide.response), (row.id, .request)] {
            do { _ = try await service.blobDownload(id: id, side: side); throw failure() }
            catch BackendAPIError.status(404) { }
        }
        let saved = try await save(session: session, manifest: manifest, directory: directory, name: "source-original-4-response.bin")
        let wrong = try TrafficBlobDownload(trafficID: row.id, side: .response, expectedSize: manifest.expectedSize + 1, expectedSHA256: manifest.expectedSHA256)
        do {
            let receipt = try await session.authenticatedTrafficBlobExport(wrong, destination: .init(newFileURL: directory.appendingPathComponent("source-bad-length.bin")))
            try receipt.discard(); throw failure()
        } catch BackendAPIError.invalidResponse { }
        guard !FileManager.default.fileExists(atPath: directory.appendingPathComponent("source-bad-length.bin").path) else { throw failure() }
        let pending = try await session.authenticatedTrafficBlobExport(manifest, destination: .init(newFileURL: directory.appendingPathComponent("source-must-not-publish.bin")))
        try authenticationWitness()
        return Result(session: session, authenticationWitness: authenticationWitness, manifest: manifest, row: row, directory: directory, saved: saved, pending: pending)
    }
    private static func save(session: AuthenticationSession, manifest: TrafficBlobDownload, directory: URL, name: String) async throws -> URL {
        let destination = directory.appendingPathComponent(name)
        let receipt = try await session.authenticatedTrafficBlobExport(manifest, destination: .init(newFileURL: destination))
        let saved = try receipt.commit(); try receipt.discard()
        let expected = try CapturedProbeContract.bytes(4, side: .response)
        guard saved.byteCount == expected.count, saved.sha256 == ArtifactIntegrity.sha256(expected), saved.stagingCleanupComplete,
              saved.directorySynced, try Data(contentsOf: saved.url) == expected else { throw failure() }
        return saved.url
    }
    private static func failure() -> RuntimeError { .integrity("owned source blob proof") }
}
#endif
