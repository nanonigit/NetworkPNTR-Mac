import ArtexCore
import Foundation
import Observation

typealias TrafficBodyMetadataLoader = @MainActor (String, FindingEvidenceSide) async throws -> TrafficBlobDownload
typealias TrafficBodyExporter = @MainActor (TrafficBlobDownload, EvidenceExportDestination) async throws -> EvidenceExportReceipt

struct TrafficBodyExportScope: Sendable, Equatable {
    let presentation: UUID
    let storeOwner: UUID
    let detailRevision: UUID
    let trafficID: String
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.presentation == rhs.presentation && lhs.storeOwner == rhs.storeOwner &&
        lhs.detailRevision == rhs.detailRevision && Data(lhs.trafficID.utf8) == Data(rhs.trafficID.utf8)
    }
}

/// One detail owner retains this model until its canceled transfer has drained.
@MainActor @Observable final class TrafficBodyExportModel {
    let id = UUID()
    let scope: TrafficBodyExportScope
    private(set) var isActive = true
    private(set) var isExporting = false
    private(set) var saved: SavedEvidenceFile?
    private(set) var failure: AppErrorMessage?
    private(set) var cleanupRequired = false
    @ObservationIgnored private let isCurrent: @MainActor (TrafficBodyExportScope, FindingEvidenceSide) -> Bool
    @ObservationIgnored private let available: @MainActor () -> Bool
    @ObservationIgnored private let metadata: @MainActor (String, FindingEvidenceSide) async throws -> TrafficBlobDownload
    @ObservationIgnored private let exporter: @MainActor (TrafficBlobDownload, EvidenceExportDestination) async throws -> EvidenceExportReceipt
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var chooser: (any EvidenceDestinationChoosing)?
    @ObservationIgnored private var cancelled = false
    @ObservationIgnored private var changing = false
    @ObservationIgnored private var acquiring = false
    @ObservationIgnored private var stopRequested = false
    @ObservationIgnored private var stopping = false
    @ObservationIgnored private var cancelling = false

    init(scope: TrafficBodyExportScope, isCurrent: @escaping @MainActor (TrafficBodyExportScope, FindingEvidenceSide) -> Bool,
         available: @escaping @MainActor () -> Bool,
         metadata: @escaping @MainActor (String, FindingEvidenceSide) async throws -> TrafficBlobDownload,
         exporter: @escaping @MainActor (TrafficBlobDownload, EvidenceExportDestination) async throws -> EvidenceExportReceipt) {
        self.scope = scope; self.isCurrent = isCurrent; self.available = available
        self.metadata = metadata; self.exporter = exporter
    }
    private func transition(_ body: () -> Void) {
        precondition(!changing)
        changing = true; body(); changing = false
        if stopRequested { stopRequested = false; stop() }
    }
    private func validate(_ side: FindingEvidenceSide) throws {
        try Task.checkCancellation()
        guard isActive, !cancelled, !stopRequested, isCurrent(scope, side), available(),
              isActive, !cancelled, !stopRequested else { throw CancellationError() }
    }
    private func eligible(_ side: FindingEvidenceSide) -> Bool {
        isActive && !cleanupRequired && !changing && !stopping && !isExporting && !Task.isCancelled && isCurrent(scope, side) && available()
            && isActive && !changing && !stopping && !isExporting && !stopRequested
    }
    func canStart(_ side: FindingEvidenceSide) -> Bool {
        guard !acquiring else { return false }
        acquiring = true; defer { acquiring = false }
        return eligible(side)
    }
    @discardableResult func start(_ side: FindingEvidenceSide, owner: UUID, chooser: any EvidenceDestinationChoosing) -> Bool {
        guard owner == id, !acquiring, isActive, !cleanupRequired, !changing, !stopping, !isExporting else { return false }
        acquiring = true; defer { acquiring = false }
        cancelled = false
        guard eligible(side), !cancelled else { return false }
        transition {
            self.chooser = chooser
            isExporting = true; saved = nil; failure = nil
            task = Task { [weak self] in
                guard let self else { return }
                defer { self.transition { self.task = nil; self.chooser = nil; self.isExporting = false } }
                do {
                    try self.validate(side)
                    let manifest = try await self.metadata(self.scope.trafficID, side)
                    try self.validate(side)
                    guard manifest.identity == Data(self.scope.trafficID.utf8), manifest.side == side else { throw BackendAPIError.invalidResponse }
                    guard let url = await chooser.choose(suggestedFilename: manifest.suggestedFilename) else { return }
                    try self.validate(side)
                    let receipt = try await self.exporter(manifest, EvidenceExportDestination(newFileURL: url))
                    do {
                        try self.validate(side)
                        guard receipt.result.status == 200, receipt.result.byteCount == manifest.expectedSize,
                              receipt.result.sha256 == manifest.expectedSHA256 else { throw EvidenceExportError.integrity }
                        let file = try receipt.commit { try self.validate(side) }
                        self.transition { self.saved = file }
                    } catch { try receipt.discard(); throw error }
                } catch {
                    if case EvidenceExportError.cleanupRequired = error {
                        self.transition { self.cleanupRequired = true; self.failure = AppErrorMessage(key: .evidenceUICleanupFailed) }
                    } else if self.isActive, !(error is CancellationError) {
                        self.transition { self.failure = AppErrorMessage(error, fallback: .evidenceUIExportFailed) }
                    }
                }
            }
        }
        return true
    }
    func cancel() {
        guard !cancelling else { return }
        cancelling = true; cancelled = true
        task?.cancel(); chooser?.cancel()
        cancelling = false
    }
    func stop() {
        guard !stopping else { return }
        if changing { stopRequested = true; cancel(); return }
        stopping = true
        transition { cancel(); isActive = false; saved = nil }
        stopping = false
    }
}
