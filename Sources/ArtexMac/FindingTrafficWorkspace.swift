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
    @ObservationIgnored private var transitioning = false
    @ObservationIgnored private var stopRequested = false
    @ObservationIgnored private var stopping = false
    @ObservationIgnored private var cancelling = false

    init(target: FindingRecord, contextTaskID: String? = nil, service: FindingTrafficService, exporter: FindingEvidenceExporter? = nil) throws {
        guard target.findingId != nil else { throw FindingInputError.readOnly }
        self.target = target; self.contextTaskID = contextTaskID; self.exporter = exporter
        store = FindingTrafficStore(service:service)
        guard store.select(target,contextTaskID:contextTaskID) else { throw FindingInputError.readOnly }
    }
    private var usable: Bool { isActive && !transitioning && !stopping && !isReading && !isExporting && !Task.isCancelled }
    /// Observation callbacks can synchronously depart during willSet. Drain departure after the entire publication.
    private func transition(_ update: () -> Void) {
        precondition(!transitioning)
        transitioning = true
        defer {
            transitioning = false
            if stopRequested { stopRequested = false; stop() }
        }
        update()
    }
    private var currentBinding: FindingTrafficBinding? {
        guard !store.summary.isStale, !store.detail.isStale,
              let detail = store.detail.value, detail.binding.id == store.selectedBindingID,
              store.summary.value?.bindings.contains(where: { $0.id == detail.binding.id && $0.snapshotId == detail.binding.snapshotId }) == true else { return nil }
        return detail.binding
    }
    func preview(_ side: FindingEvidenceSide) -> EvidenceTextPreview? { side == .request ? requestPreview : responsePreview }
    func refresh() async {
        guard usable else { return }
        let revision = readRevision
        transition { isReading = true }
        defer { if readRevision == revision { transition { isReading = false } } }
        guard isActive, readRevision == revision else { return }
        await store.refreshSummary()
        guard isActive, readRevision == revision, !Task.isCancelled else { return }
        transition { requestPreview = nil; responsePreview = nil; saved = nil; failure = store.summary.failure }
    }
    func selectBinding(_ bindingID: String?, owner: UUID) async {
        guard usable, owner == id, !store.summary.isStale else { return }
        let revision = readRevision
        var selected = false
        transition {
            selected = store.selectBinding(bindingID,owner:store.owner)
            if selected {
                requestPreview = nil; responsePreview = nil; failure = nil; saved = nil
                isReading = bindingID != nil
            }
        }
        guard isActive, readRevision == revision, selected, bindingID != nil else { return }
        defer { if readRevision == revision { transition { isReading = false } } }
        await store.refreshDetail()
        guard isActive, readRevision == revision, !Task.isCancelled else { return }
        transition {
            failure = store.detail.failure
            if let value = currentBinding, let detail = store.detail.value, value.id == detail.binding.id {
                requestPreview = EvidenceTextPreview(detail.request); responsePreview = EvidenceTextPreview(detail.response)
            }
        }
    }
    func more(_ side: FindingEvidenceSide, owner: UUID) async {
        guard usable, owner == id, currentBinding != nil, let value = preview(side), value.hasMore else { return }
        let revision = readRevision
        var configured = false
        transition {
            configured = store.configureBody(side:side,offset:value.nextOffset,owner:store.owner)
            if configured { isReading = true }
        }
        guard isActive, readRevision == revision, configured else { return }
        defer { if readRevision == revision { transition { isReading = false } } }
        await store.refreshBody()
        guard isActive, readRevision == revision, !Task.isCancelled else { return }
        transition {
            failure = store.body.failure
            guard !store.body.isStale, let page = store.body.value else { return }
            do {
                var updated = value; try updated.append(page)
                if side == .request { requestPreview = updated } else { responsePreview = updated }
            } catch { failure = AppErrorMessage(error) }
        }
    }
    @discardableResult func startExport(_ side: FindingEvidenceSide, owner: UUID, chooser: any EvidenceDestinationChoosing) -> Bool {
        guard usable, owner == id, let exporter, let binding = currentBinding else { return false }
        let manifest: FindingEvidenceDownload
        do { manifest = try FindingEvidenceDownload(binding:binding,side:side,contextTaskID:contextTaskID) }
        catch { failure = AppErrorMessage(error,fallback:.evidenceUIExportFailed); return false }
        transition {
          let revision = UUID(); exportRevision = revision; self.chooser = chooser
          isExporting = true; failure = nil; saved = nil
          exportTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.exportRevision == revision {
                    self.transition { self.isExporting = false; self.exportTask = nil; self.chooser = nil }
                }
            }
            do {
                try self.validateExport(revision,binding:binding)
                guard let url = await chooser.choose(suggestedFilename:manifest.suggestedFilename) else { return }
                try self.validateExport(revision,binding:binding)
                let destination = try EvidenceExportDestination(newFileURL:url)
                let receipt = try await exporter(manifest,destination)
                do {
                    try self.validateExport(revision,binding:binding)
                    guard receipt.result.status == 200, receipt.result.byteCount == manifest.expectedSize,
                          receipt.result.sha256 == manifest.expectedSHA256 else { throw EvidenceExportError.integrity }
                    let file = try receipt.commit { try self.validateExport(revision,binding:binding) }
                    self.transition { self.saved = file }
                } catch { try receipt.discard(); throw error }
            } catch {
                guard self.isActive, self.exportRevision == revision else { return }
                self.transition {
                    if case EvidenceExportError.cleanupRequired = error {
                        self.failure = AppErrorMessage(key:.evidenceUICleanupFailed)
                    } else if !(error is CancellationError) {
                        self.failure = AppErrorMessage(error,fallback:error is EvidenceExportError ? .evidenceUIExportFailed : .errorCommunication)
                    }
                }
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
    func cancelExport() {
        guard !cancelling else { return }
        cancelling = true
        defer { cancelling = false }
        exportTask?.cancel(); chooser?.cancel()
    }
    func stop() {
        guard !stopping else { return }
        if transitioning { stopRequested = true; return }
        stopping = true
        defer { stopping = false }
        isActive = false; readRevision = UUID(); isReading = false
        cancelExport(); store.reset(); requestPreview = nil; responsePreview = nil; failure = nil; saved = nil
    }
}
