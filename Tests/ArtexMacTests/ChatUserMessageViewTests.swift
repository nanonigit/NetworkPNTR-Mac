import AppKit
import SwiftUI
import XCTest
@testable import ArtexCore
@testable import ArtexMac

final class ChatUserMessageViewTests: XCTestCase {
    @MainActor private func labels(_ object: Any, depth: Int = 0) -> [(String, String)] {
        guard depth < 20, let element = object as? any NSAccessibilityProtocol else { return [] }
        let role = element.accessibilityRole()?.rawValue ?? ""
        let label = element.accessibilityLabel() ?? ""
        let text = label.isEmpty ? (element.accessibilityValue() as? String) ?? "" : label
        return [(role, text)] + (element.accessibilityChildren() ?? []).flatMap { labels($0, depth: depth + 1) }
    }
    @MainActor func testReadOnlyCardsRenderDuplicateMetadataWithoutRemoveButtons() async throws {
        let file = try ChatAttachment(name: "fixture.txt", path: "uploads/fixture.txt", size: 51)
        let view = NSHostingView(rootView: ChatAttachmentStrip(attachments: [file, file]))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 180), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        defer { window.close() }
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let values = labels(view)
        XCTAssertEqual(values.filter { $0.1 == "fixture.txt" }.count, 2)
        XCTAssertEqual(values.filter { $0.1 == "51 B" }.count, 2)
        XCTAssertFalse(values.contains { $0.0 == NSAccessibility.Role.button.rawValue })
    }
}
