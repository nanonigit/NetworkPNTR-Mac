import ArtexCore
import Foundation
import Observation

@MainActor protocol EvidenceDestinationChoosing: AnyObject {
    func choose(suggestedFilename: String) async -> URL?
    func cancel()
}

typealias FindingEvidenceExporter = @MainActor (FindingEvidenceDownload, EvidenceExportDestination) async throws -> EvidenceExportReceipt

struct EvidenceTextPreview {
    private(set) var content: String
    private(set) var nextOffset: Int64
    let total: Int64
    private(set) var binary: Bool
    var hasMore: Bool { !binary && nextOffset < total }
    init(_ value: FindingEvidencePreview) {
        content = value.content; nextOffset = value.nextOffset; total = value.total; binary = value.binary
    }
    mutating func append(_ value: FindingEvidencePreview) throws {
        guard value.offset == nextOffset, value.total == total else { throw BackendAPIError.invalidResponse }
        content += value.content; nextOffset = value.nextOffset; binary = binary || value.binary
    }
}

/// A fixed finding belongs to one presented sheet; neither server paths nor callbacks select a new owner.
@MainActor @Observable final class FindingTrafficWorkspace: Identifiable {
    let id = UUID()
    let target: FindingRecord
    let store: FindingTrafficStore
    private(set) var isActive = true
    private(set) var isReading = false
    private(set) var isExporting = false
    private(set) var failure: AppErrorMessage?
    private(set) var saved: SavedEvidenceFile?
    var canExport: Bool { exporter != nil && usable && currentBinding != nil }
    var requestHeader: String { currentBinding?.snapshot.requestHead ?? "" }
    var responseHeader: String { currentBinding?.snapshot.responseHead ?? "" }
    @ObservationIgnored private let exporter: FindingEvidenceExporter?
    @ObservationIgnored private let contextTaskID: String?
    private var requestPreview: EvidenceTextPreview?
    private var responsePreview: EvidenceTextPreview?
    @ObservationIgnored private var readRevision = UUID()
    @ObservationIgnored private var exportTask: Task<Void, Never>?
    @ObservationIgnored private var chooser: (any EvidenceDestinationChoosing)?
    @ObservationIgnored private var exportRevision = UUID()

    init(target: FindingRecord, contextTaskID: String? = nil, service: FindingTrafficService, exporter: FindingEvidenceExporter? = nil) throws {
        guard target.findingId != nil else { throw FindingInputError.readOnly }
        self.target = target; self.contextTaskID = contextTaskID; self.exporter = exporter
        store = FindingTrafficStore(service:service)
        guard store.select(target,contextTaskID:contextTaskID) else { throw FindingInputError.readOnly }
    }
    private var usable: Bool { isActive && !isReading && !isExporting && !Task.isCancelled }
    private var currentBinding: FindingTrafficBinding? {
        guard !store.summary.isStale, !store.detail.isStale,
              let detail = store.detail.value, detail.binding.id == store.selectedBindingID,
              store.summary.value?.bindings.contains(where: { $0.id == detail.binding.id && $0.snapshotId == detail.binding.snapshotId }) == true else { return nil }
        return detail.binding
    }
    func preview(_ side: FindingEvidenceSide) -> EvidenceTextPreview? { side == .request ? requestPreview : responsePreview }
    func refresh() async {
        guard usable else { return }
        isReading = true; let revision = readRevision
        defer { if readRevision == revision { isReading = false } }
        await store.refreshSummary()
        guard isActive, readRevision == revision, !Task.isCancelled else { return }
        requestPreview = nil; responsePreview = nil; saved = nil; failure = store.summary.failure
    }
    func selectBinding(_ bindingID: String?, owner: UUID) async {
        guard usable, owner == id, !store.summary.isStale, store.selectBinding(bindingID,owner:store.owner) else { return }
        requestPreview = nil; responsePreview = nil; failure = nil; saved = nil
        guard bindingID != nil else { return }
        isReading = true; let revision = readRevision
        defer { if readRevision == revision { isReading = false } }
        await store.refreshDetail()
        guard isActive, readRevision == revision, !Task.isCancelled else { return }
        failure = store.detail.failure
        if let value = currentBinding, let detail = store.detail.value, value.id == detail.binding.id {
            requestPreview = EvidenceTextPreview(detail.request); responsePreview = EvidenceTextPreview(detail.response)
        }
    }
    func more(_ side: FindingEvidenceSide, owner: UUID) async {
        guard usable, owner == id, currentBinding != nil, let value = preview(side), value.hasMore,
              store.configureBody(side:side,offset:value.nextOffset,owner:store.owner) else { return }
        isReading = true; let revision = readRevision
        defer { if readRevision == revision { isReading = false } }
        await store.refreshBody()
        guard isActive, readRevision == revision, !Task.isCancelled else { return }
        failure = store.body.failure
        guard !store.body.isStale, let page = store.body.value else { return }
        do {
            var updated = value; try updated.append(page)
            if side == .request { requestPreview = updated } else { responsePreview = updated }
        } catch { failure = AppErrorMessage(error) }
    }
    @discardableResult func startExport(_ side: FindingEvidenceSide, owner: UUID, chooser: any EvidenceDestinationChoosing) -> Bool {
        guard usable, owner == id, let exporter, let binding = currentBinding else { return false }
        let manifest: FindingEvidenceDownload
        do { manifest = try FindingEvidenceDownload(binding:binding,side:side,contextTaskID:contextTaskID) }
        catch { failure = AppErrorMessage(error,fallback:.evidenceUIExportFailed); return false }
        let revision = UUID(); exportRevision = revision; self.chooser = chooser
        isExporting = true; failure = nil; saved = nil
        exportTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.exportRevision == revision { self.isExporting = false; self.exportTask = nil; self.chooser = nil }
            }
            do {
                guard let url = await chooser.choose(suggestedFilename:manifest.suggestedFilename) else { return }
                try self.validateExport(revision,binding:binding)
                let destination = try EvidenceExportDestination(newFileURL:url)
                let receipt = try await exporter(manifest,destination)
                do {
                    try self.validateExport(revision,binding:binding)
                    self.saved = try receipt.commit { try self.validateExport(revision,binding:binding) }
                } catch { try receipt.discard(); throw error }
            } catch {
                guard self.isActive, self.exportRevision == revision else { return }
                if case EvidenceExportError.cleanupRequired = error {
                    self.failure = AppErrorMessage(key:.evidenceUICleanupFailed)
                } else if !(error is CancellationError) {
                    self.failure = AppErrorMessage(error,fallback:error is EvidenceExportError ? .evidenceUIExportFailed : .errorCommunication)
                }
            }
        }
        return true
    }
    private func validateExport(_ revision: UUID, binding: FindingTrafficBinding) throws {
        try Task.checkCancellation()
        guard isActive, exportRevision == revision, let current = currentBinding,
              current.id == binding.id, current.snapshotId == binding.snapshotId,
              current.snapshot.requestHash == binding.snapshot.requestHash, current.snapshot.responseHash == binding.snapshot.responseHash,
              current.snapshot.requestLength == binding.snapshot.requestLength, current.snapshot.responseLength == binding.snapshot.responseLength else { throw CancellationError() }
    }
    func cancelExport() { exportTask?.cancel(); chooser?.cancel() }
    func stop() {
        isActive = false; readRevision = UUID(); isReading = false
        cancelExport(); store.reset(); requestPreview = nil; responsePreview = nil; failure = nil; saved = nil
    }
}
