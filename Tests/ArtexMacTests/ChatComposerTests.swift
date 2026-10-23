import AppKit
import ArtexCore
import SwiftUI
import XCTest
@testable import ArtexMac

final class ChatComposerTests: XCTestCase {
    @MainActor final class Transport: BackendJSONTransport {
        func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
            BackendHTTPResponse(status: 200, body: Data(#"{"items":[],"cursor":0,"running":false,"hasMore":false}"#.utf8))
        }
    }
    @MainActor func testMarkedTextCallbackKeepsOriginalConversationBindingAfterSelectionChanges() async throws {
        let store = ChatStore(service: ChatService(client: Transport()))
        await store.select(id: 7); store.draft = "conversation A"
        let composer = ChatComposer(text: ChatComposer.draftBinding(store: store, conversationID: 7), mode: "enter", disabled: false, send: {})
        let coordinator = ChatComposer.Coordinator(composer)
        let editor = ChatComposer.Editor(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
        editor.setMarkedText("変換中", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText())
        await store.select(id: 8); store.draft = "conversation B"
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        XCTAssertEqual(store.draft, "conversation B")
        XCTAssertEqual(store.draft(for: 7), "変換中")
    }
    @MainActor func testMentionReturnIsConsumedBeforeSendAndCompositionSkipsHandler() throws {
        let editor = ChatComposer.Editor(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
        var handled = 0; var sent = 0
        editor.isEditable = true; editor.submit = { sent += 1 }
        editor.handleMentionKey = { _ in handled += 1; return true }
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        editor.keyDown(with: event)
        XCTAssertEqual(handled, 1); XCTAssertEqual(sent, 0)
        editor.setMarkedText("変換中", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertFalse(editor.consumeMentionKey(event)); XCTAssertEqual(handled, 1)
    }
    @MainActor func testEditingCallbackReportsCaretAndCompositionUsingOriginalBinding() {
        var text = ""; var observations: [(String, Int, Bool)] = []
        let composer = ChatComposer(text: Binding(get: { text }, set: { text = $0 }), mode: "enter", disabled: false, send: {}, onEditing: { value, range, composing in observations.append((value, range.location, composing)) })
        let coordinator = ChatComposer.Coordinator(composer)
        let editor = ChatComposer.Editor(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
        editor.string = "😀 @finding"; editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        XCTAssertEqual(text, "😀 @finding"); XCTAssertEqual(observations.last?.1, text.utf16.count)
        editor.setMarkedText("変換中", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        XCTAssertEqual(observations.last?.2, true)
    }

    @MainActor func testRepeatedIdenticalCitationRestoresCaretAfterInterveningTyping() throws {
        var text = ""
        let parent = ChatComposer(text: Binding(get: { text }, set: { text = $0 }), mode: "enter", disabled: false, send: {})
        let coordinator = ChatComposer.Coordinator(parent)
        let editor = ChatComposer.Editor(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
        let query = "@finding"
        let active = try XCTUnwrap(ChatMentionEditing.active(in: query, caret: query.utf16.count))
        let edit = try XCTUnwrap(ChatMentionEditing.replace(in: query, active: active, with: "@[漏洞#9 record] "))
        editor.string = edit.text; coordinator.applySelection(edit, to: editor, text: edit.text)
        XCTAssertEqual(editor.selectedRange().location, edit.caret)
        editor.string = query
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        editor.string = edit.text; editor.setSelectedRange(NSRange(location: 0, length: 0))
        coordinator.applySelection(edit, to: editor, text: edit.text)
        XCTAssertEqual(editor.selectedRange().location, edit.caret)
    }

    @MainActor func testConsumedCitationSelectionDoesNotReplayAfterUndoRestoresText() throws {
        var text = ""
        let parent = ChatComposer(text: Binding(get: { text }, set: { text = $0 }), mode: "enter", disabled: false, send: {})
        let coordinator = ChatComposer.Coordinator(parent)
        let editor = ChatComposer.Editor(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
        let query = "@finding suffix"
        let active = try XCTUnwrap(ChatMentionEditing.active(in: query, caret: 8))
        let edit = try XCTUnwrap(ChatMentionEditing.replace(in: query, active: active, with: "@[漏洞#9 record] "))
        editor.string = edit.text; coordinator.applySelection(edit, to: editor, text: edit.text)
        editor.string = edit.text + "x"
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        editor.string = edit.text; editor.setSelectedRange(NSRange(location: edit.text.utf16.count, length: 0))
        coordinator.applySelection(edit, to: editor, text: edit.text)
        XCTAssertEqual(editor.selectedRange().location, edit.text.utf16.count)
    }

}
