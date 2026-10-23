import AppKit
import ArtexCore
import SwiftUI

/// SwiftUI owns the draft; AppKit supplies marked-text and native editing semantics.
struct ChatComposer: NSViewRepresentable {
    @Binding var text: String
    let mode: String
    let disabled: Bool
    let send: () -> Void
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
        editor.delegate = context.coordinator; editor.setAccessibilityLabel("メッセージ")
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? Editor else { return }
        if editor.string != text, !editor.hasMarkedText() { editor.string = text }
        editor.isEditable = !disabled; editor.mode = mode; editor.submit = send
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatComposer
        init(_ parent: ChatComposer) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            if let editor = notification.object as? NSTextView { parent.text = editor.string }
        }
    }
    final class Editor: NSTextView {
        var mode = "enter"
        var submit: (() -> Void)?
        override func keyDown(with event: NSEvent) {
            if isEditable, [36, 76].contains(event.keyCode),
               ChatSendPolicy.shouldSend(mode: mode, shift: event.modifierFlags.contains(.shift),
                    control: event.modifierFlags.contains(.control), command: event.modifierFlags.contains(.command), composing: hasMarkedText()) {
                submit?(); return
            }
            super.keyDown(with: event)
        }
    }
}
