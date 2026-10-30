import Foundation

struct EvidenceDownloadResponse: Sendable {
    let result: BackendDownloadResult
    let file: VerifiedEvidenceFile?
}

/// Owns transfer and private staging, but leaves publication to the authenticated caller.
enum EvidenceDownloadStaging {
    static func exchange(socket: BackendUploadSocket, preamble: Data, request: Data,
                         manifest: any EvidenceBodyManifest, destination: EvidenceExportDestination,
                         timeout: Duration = .seconds(300)) throws -> EvidenceDownloadResponse {
        defer { socket.finish() }
        let writer = try EvidenceExportWriter(destination: destination, request: manifest)
        let deadline = ContinuousClock.now.advanced(by: timeout)
        do {
            let result = try BackendDownloadExchange.exchange(
                socket: socket, preamble: preamble, request: request,
                expectedSize: manifest.expectedSize, maximumBytes: manifest.expectedSize,
                onBody: { bytes in
                    try writer.append(bytes)
                    #if DEBUG
                    if let transfer = TrafficBlobCancellationProbe.current {
                        guard let blob = manifest as? TrafficBlobDownload,
                              blob.identity == transfer.manifest.identity, blob.side == transfer.manifest.side,
                              blob.expectedSize == transfer.manifest.expectedSize,
                              blob.expectedSHA256 == transfer.manifest.expectedSHA256 else { throw RuntimeError.integrity("source blob interruption scope") }
                        try transfer.probe.pauseAfterAppend(operationID: transfer.operationID, manifest: blob, bytes: Int64(bytes.count))
                    }
                    #endif
                }, timeout: timeout)
            try socket.validateCompletion()
            guard result.status == 200 else {
                try writer.discard()
                return EvidenceDownloadResponse(result: result, file: nil)
            }
            let file = try writer.finish(response: result, validate: {
                try socket.validateCompletion()
                guard ContinuousClock.now < deadline else { throw RuntimeError.timeout("evidence download") }
            })
            return EvidenceDownloadResponse(result: result, file: file)
        } catch {
            try writer.discard()
            throw error
        }
    }
}
