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
}
