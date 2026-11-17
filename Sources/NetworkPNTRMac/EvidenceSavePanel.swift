import AppKit
import NetworkPNTRCore
import SwiftUI

/// The panel is bound to the presenting sheet's view, never NSApp's key window.
@MainActor final class EvidenceSavePanelPresenter: EvidenceDestinationChoosing {
    var language: AppLanguage = .english
    private weak var anchor: NSView?
    private var panel: NSSavePanel?
    private var completion: CheckedContinuation<URL?, Never>?
    private var revision = UUID()
    func attach(_ view: NSView) { anchor = view }
    func detach(_ view: NSView) {
        guard anchor === view else { return }
        cancel(); anchor = nil
    }
    func windowChanged(_ view: NSView) { if anchor === view, view.window == nil { cancel() } }
    func choose(suggestedFilename: String) async -> URL? {
        guard !Task.isCancelled, completion == nil, let window = anchor?.window,
              window.isVisible, window.attachedSheet == nil else { return nil }
        let panel = NSSavePanel(), ticket = UUID(); revision = ticket; self.panel = panel
        panel.nameFieldStringValue = suggestedFilename
        panel.title = AppStrings.text(.evidenceUIDownload,language:language)
        panel.message = AppStrings.text(.evidenceUISaveHelp,language:language)
        panel.canCreateDirectories = true
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                completion = continuation
                panel.beginSheetModal(for:window) { [weak self, weak panel] response in
                    Task { @MainActor [weak self, weak panel] in
                        guard let self, self.revision == ticket else { return }
                        self.finish(response == .OK ? panel?.url : nil)
                    }
                }
                if Task.isCancelled { cancel() }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.cancel(ticket:ticket) } }
    }
    private func cancel(ticket: UUID) { if revision == ticket { cancel() } }
    func cancel() {
        let previous = panel
        finish(nil)
        previous?.cancel(nil)
    }
    private func finish(_ url: URL?) {
        let callback = completion; completion = nil; panel = nil; revision = UUID()
        callback?.resume(returning:url)
    }
}

@MainActor private final class EvidenceAnchorView: NSView {
    weak var presenter: EvidenceSavePanelPresenter?
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); presenter?.windowChanged(self) }
}
@MainActor struct EvidenceWindowAnchor: NSViewRepresentable {
    let presenter: EvidenceSavePanelPresenter
    func makeNSView(context: Context) -> NSView {
        let view = EvidenceAnchorView(); view.presenter = presenter; presenter.attach(view); return view
    }
    func updateNSView(_ nsView: NSView,context: Context) { presenter.attach(nsView) }
    static func dismantleNSView(_ nsView: NSView,coordinator: ()) {
        if let anchor = nsView as? EvidenceAnchorView { anchor.presenter?.detach(anchor) }
    }
}
