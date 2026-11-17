import AppKit
import NetworkPNTRCore
import SwiftUI

struct ChatMentionSelection: Equatable {
    let id = UUID()
    let edit: ChatMentionEdit
}

/// SwiftUI owns the draft; AppKit supplies marked-text and native editing semantics.
struct ChatComposer: NSViewRepresentable {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }

    @Binding var text: String
    let mode: String
    let disabled: Bool
    let send: () -> Void
    var onEditing: ((String, NSRange, Bool) -> Void)? = nil
    var onMentionKey: ((NSEvent) -> Bool)? = nil
    var selectionRequest: ChatMentionSelection? = nil
    static func draftBinding(store: ChatStore, conversationID: Int64?) -> Binding<String> {
        Binding(get: { store.draft(for: conversationID) }, set: { store.setDraft($0, for: conversationID) })
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let editor = Editor(); editor.isRichText = false; editor.drawsBackground = false
        editor.font = .systemFont(ofSize: NSFont.systemFontSize); editor.textContainerInset = NSSize(width: 8, height: 8)
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator; Self.applyLanguage(to: editor, language: language)
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? Editor else { return }
        context.coordinator.updating = true
        defer { context.coordinator.updating = false }
        if editor.string != text, !editor.hasMarkedText() { editor.string = text }
        Self.applyLanguage(to: editor, language: language)
        editor.isEditable = !disabled; editor.mode = mode; editor.submit = send
        editor.handleMentionKey = onMentionKey
        context.coordinator.applySelection(selectionRequest, to: editor, text: text)
    }
    @MainActor static func applyLanguage(to editor: Editor, language: AppLanguage) {
        editor.setAccessibilityLabel(AppStrings.text(.chatMessage, language: language))
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatComposer
        var updating = false
        var appliedSelection: UUID?
        init(_ parent: ChatComposer) { self.parent = parent }
        @MainActor func applySelection(_ request: ChatMentionSelection?, to editor: Editor, text: String) {
            if let request, request.id != appliedSelection,
               request.edit.text == text, !editor.hasMarkedText(), request.edit.caret >= 0, request.edit.caret <= text.utf16.count {
                editor.setSelectedRange(NSRange(location: request.edit.caret, length: 0))
                editor.window?.makeFirstResponder(editor)
                appliedSelection = request.id
            }
        }
        func textDidChange(_ notification: Notification) {
            guard !updating, let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
            parent.onEditing?(editor.string, editor.selectedRange(), editor.hasMarkedText())
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !updating, let editor = notification.object as? NSTextView else { return }
            parent.onEditing?(editor.string, editor.selectedRange(), editor.hasMarkedText())
        }
    }
    final class Editor: NSTextView {
        var mode = "enter"
        var submit: (() -> Void)?
        var handleMentionKey: ((NSEvent) -> Bool)?
        func consumeMentionKey(_ event: NSEvent) -> Bool {
            isEditable && !hasMarkedText() && (handleMentionKey?(event) ?? false)
        }
        override func keyDown(with event: NSEvent) {
            if consumeMentionKey(event) { return }
            if event.keyCode == 48, !hasMarkedText(), event.modifierFlags.intersection([.control, .command, .option]).isEmpty {
                if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(self) }
                else { window?.selectNextKeyView(self) }
                return
            }
            if isEditable, [36, 76].contains(event.keyCode),
               ChatSendPolicy.shouldSend(mode: mode, shift: event.modifierFlags.contains(.shift),
                    control: event.modifierFlags.contains(.control), command: event.modifierFlags.contains(.command), composing: hasMarkedText()) {
                submit?(); return
            }
            super.keyDown(with: event)
        }
    }
}
