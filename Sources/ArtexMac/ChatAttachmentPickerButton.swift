import AppKit
import SwiftUI
import ArtexCore

/// The panel belongs to the clicked button's window and immutable conversation callback.
struct ChatAttachmentPickerButton: NSViewRepresentable {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }

    let enabled: Bool
    let onChoose: ([URL]) -> Void
    let onPresentation: (Bool) -> Void
    let onError: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: s(.chatAttach), target: context.coordinator, action: #selector(Coordinator.pick(_:)))
        button.bezelStyle = .rounded
        button.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        Self.applyLanguage(to: button, language: language)
        button.isEnabled = enabled
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self; button.isEnabled = enabled
        Self.applyLanguage(to: button, language: language)
    }
    static func dismantleNSView(_ button: NSButton, coordinator: Coordinator) { coordinator.invalidate() }
    @MainActor static func applyLanguage(to button: NSButton, language: AppLanguage) {
        let title = AppStrings.text(.chatAttach, language: language)
        button.title = title; button.setAccessibilityLabel(title); button.toolTip = title
    }
    static func makePanel(language: AppLanguage = .japanese) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true; panel.treatsFilePackagesAsDirectories = true
        panel.prompt = AppStrings.text(.chatAttachPrompt, language: language); panel.message = AppStrings.text(.chatAttachMessage, language: language)
        return panel
    }
    @MainActor final class Coordinator: NSObject {
        var parent: ChatAttachmentPickerButton
        private var panel: NSOpenPanel?
        private var ticket: UUID?
        init(_ parent: ChatAttachmentPickerButton) { self.parent = parent }
        @objc func pick(_ button: NSButton) {
            guard parent.enabled, panel == nil else { return }
            guard let window = button.window else { parent.onError(); return }
            let panel = ChatAttachmentPickerButton.makePanel(language: parent.language), ticket = UUID()
            let choose = parent.onChoose, presented = parent.onPresentation
            self.panel = panel; self.ticket = ticket; presented(true)
            panel.beginSheetModal(for: window) { [weak self, weak panel] response in
                guard let self, let panel, self.ticket == ticket else { return }
                self.panel = nil; self.ticket = nil; presented(false)
                if response == .OK, !panel.urls.isEmpty { choose(panel.urls) }
            }
        }
        func invalidate() {
            ticket = nil
            let owned = panel; panel = nil
            owned?.cancel(nil)
            // SwiftUI owns presentation state on selection/disappearance. Do not
            // mutate it from dismantleNSView or an obsolete completion.
        }
    }
}
