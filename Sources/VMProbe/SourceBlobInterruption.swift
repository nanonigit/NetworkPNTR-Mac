#if DEBUG
import NetworkPNTRCore
import Foundation

/// Exercises controlled partial staging over the actual guest transport, not UI acceptance.
@MainActor enum SourceBlobInterruption {
    struct Proof {
        let partial: TrafficBlobCancellationProbe.Partial
        let manifest: TrafficBlobDownload
        var report: [String: Any] {
            ["controlledReaderPause": true, "operationID": partial.operationID.uuidString,
             "stagedBytes": partial.bytes, "expectedBytes": manifest.expectedSize,
             "sha256": manifest.expectedSHA256, "trafficIdentitySHA256": ArtifactIntegrity.sha256(manifest.identity),
             "openSocketInterrupted": true, "authenticationUnchanged": true,
             "destinationAbsent": true, "stagingAbsent": true, "vmStillRunning": true,
             "naturalNetworkFailureVerified": false, "nativeUIAcceptance": false]
        }
    }
    /// Claims only the diagnostic slot; the caller checks live VM state without suspending.
    static func claimProbe(_ probe: TrafficBlobCancellationProbe, controller: VMController) throws {
        guard controller.trafficBlobCancellationProbe == nil else { throw failure() }
        controller.trafficBlobCancellationProbe = probe
    }
    static func run(session: AuthenticationSession, api: any BackendJSONTransport, row: CapturedTrafficExchange,
                    directory: URL, controller: VMController) async throws -> Proof {
        try Task.checkCancellation()
        guard controller.state == .running, controller.guestReady, controller.hasMachine,
              controller.trafficBlobCancellationProbe == nil else { throw failure() }
        let authenticationWitness = try session.exportOwnershipWitness()
        let manifest = try await TrafficService(client: api).blobDownload(id: row.id, side: .response)
        try SourceBlobProbe.validateManifest(manifest, row: row)
        try authenticationWitness()
        let destination = directory.appendingPathComponent("source-controlled-interruption.bin")
        guard !FileManager.default.fileExists(atPath: destination.path), EvidenceProbeFile.stagingAbsent(directory) else { throw failure() }
        let probe = TrafficBlobCancellationProbe(expected: manifest)
        guard controller.state == .running, controller.guestReady, controller.hasMachine else { throw failure() }
        try claimProbe(probe, controller: controller)
        defer { if controller.trafficBlobCancellationProbe === probe { controller.trafficBlobCancellationProbe = nil } }
        var settled = false
        let pending = Task { @MainActor in
            defer { settled = true }
            return try await session.authenticatedTrafficBlobExport(manifest, destination: .init(newFileURL: destination))
        }
        do {
            var partial: TrafficBlobCancellationProbe.Partial?
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while ContinuousClock.now < deadline {
                if let value = probe.partial { partial = value; break }
                if settled { break }
                try await Task.sleep(for: .milliseconds(1))
            }
            guard let partial, !settled, partial.bytes > 0, partial.bytes < manifest.expectedSize else { throw failure() }
            try Task.checkCancellation(); try authenticationWitness()
            pending.cancel()
            do { let receipt = try await pending.value; try receipt.discard(); throw failure() }
            catch is CancellationError { }
            try Task.checkCancellation(); try authenticationWitness()
            guard probe.witness == partial, controller.state == .running, controller.guestReady, controller.hasMachine,
                  !FileManager.default.fileExists(atPath: destination.path), EvidenceProbeFile.stagingAbsent(directory) else { throw failure() }
            return Proof(partial: partial, manifest: manifest)
        } catch {
            let original = error
            pending.cancel()
            do { let receipt = try await pending.value; try receipt.discard() }
            catch is CancellationError { }
            catch { throw error }
            throw original
        }
    }
    private static func failure() -> RuntimeError { .integrity("source blob controlled interruption proof") }
}
#endif
