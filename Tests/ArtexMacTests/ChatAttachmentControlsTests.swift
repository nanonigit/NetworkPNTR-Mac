import AppKit
import SwiftUI
import XCTest
@testable import ArtexCore
@testable import ArtexMac

final class ChatAttachmentControlsTests: XCTestCase {
    private func availability() -> ChatComposerAvailability {
        .init(draft: "", attachmentCount: 1, isNewConversation: false, hasAgent: true,
              historyReady: true, busy: false, sending: false, running: false, uploading: false, picking: false)
    }
    func testAttachmentOnlyAndUnicodeSendGuardUseSameAvailabilityForKeyAndButton() {
        var value = availability()
        XCTAssertTrue(value.canSend); XCTAssertTrue(value.canPick)
        value.attachmentCount = 0; value.draft = "\u{FEFF}"
        XCTAssertFalse(value.canSend)
        value.draft = "\u{85}"; XCTAssertTrue(value.canSend)
        value.draft = "\u{200B}"; XCTAssertTrue(value.canSend)
        value.isNewConversation = true; value.hasAgent = false
        XCTAssertFalse(value.canSend); XCTAssertFalse(value.canPick)
    }
    func testBusyHistoryAndUploadGuardsDoNotDisableExistingUploadEdits() {
        let ready = availability()
        for mutate: (inout ChatComposerAvailability) -> Void in [
            { $0.busy = true }, { $0.sending = true }, { $0.running = true },
            { $0.uploading = true }, { $0.picking = true }, { $0.historyReady = false }
        ] {
            var value = ready; mutate(&value)
            XCTAssertFalse(value.canSend); XCTAssertFalse(value.canPick)
        }
        var uploading = ready; uploading.uploading = true
        XCTAssertFalse(uploading.editorDisabled)
        uploading.isNewConversation = true; XCTAssertTrue(uploading.editorDisabled)
        var new = ready; new.isNewConversation = true; new.historyReady = false
        XCTAssertTrue(new.canSend); XCTAssertTrue(new.canPick)
    }
    func testProgressNeverDescribesBodyWrittenAsSaved() {
        let pending = ChatUploadPresentation(progress: nil)
        XCTAssertNil(pending.fraction); XCTAssertEqual(pending.title, "ファイルを準備中…")
        let partial = ChatUploadPresentation(progress: .init(sentBodyBytes: 512, totalBodyBytes: 1024))
        XCTAssertEqual(partial.fraction, 0.5); XCTAssertEqual(partial.title, "アップロード中…")
        XCTAssertEqual(partial.detail, "512 B / 1.0 KB")
        let written = ChatUploadPresentation(progress: .init(sentBodyBytes: 1024, totalBodyBytes: 1024))
        XCTAssertEqual(written.fraction, 1); XCTAssertEqual(written.title, "添付を処理中…")
        let invalid = ChatUploadPresentation(progress: .init(sentBodyBytes: 3, totalBodyBytes: 0))
        XCTAssertNil(invalid.fraction)
    }
    func testByteSizesMatchPinnedBrowserThresholds() {
        for (bytes, expected): (Int64, String) in [(0,"0 B"),(1023,"1023 B"),(1024,"1.0 KB"),(1536,"1.5 KB"),(1048576,"1.0 MB"),(134217728,"128.0 MB")] {
            XCTAssertEqual(ChatAttachmentPresentation.bytes(bytes), expected)
        }
    }
    @MainActor func testScopesStayOpenDuringOperationAndReleaseOnlyStartedScopesOnError() async throws {
        let files = [URL(fileURLWithPath: "/fixture/a"), URL(fileURLWithPath: "/fixture/b")]
        var events: [String] = []
        let access = ChatFileAccess(start: { url in events.append("start " + url.lastPathComponent); return url == files[0] },
                                    stop: { url in events.append("stop " + url.lastPathComponent) })
        do {
            try await access.withAccess(files) {
                XCTAssertEqual(events, ["start a","start b"])
                await Task.yield()
                XCTAssertEqual(events, ["start a","start b"])
                throw CocoaError(.fileReadUnknown)
            }
            XCTFail("Expected fixture failure")
        } catch {}
        XCTAssertEqual(events, ["start a","start b","stop a"])
    }
    @MainActor func testCancellationAndSuccessReleaseFileAccess() async throws {
        let files = [URL(fileURLWithPath: "/fixture/a")]
        var starts = 0, stops = 0, entered = false
        let access = ChatFileAccess(start: { _ in starts += 1; return true }, stop: { _ in stops += 1 })
        let task = Task { try await access.withAccess(files) { entered = true; try await Task.sleep(for: .seconds(5)) } }
        for _ in 0..<2000 { if entered { break }; await Task.yield() }
        XCTAssertTrue(entered); XCTAssertEqual(stops, 0)
        task.cancel()
        do { try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(starts, 1); XCTAssertEqual(stops, 1)
        let value = try await access.withAccess(files) { 42 }
        XCTAssertEqual(value, 42); XCTAssertEqual(starts, 2); XCTAssertEqual(stops, 2)
    }
    @MainActor func testNativePanelIsMultipleFilesOnlyAndWindowlessClickIsSafe() {
        let panel = ChatAttachmentPickerButton.makePanel()
        XCTAssertTrue(panel.canChooseFiles); XCTAssertFalse(panel.canChooseDirectories)
        XCTAssertTrue(panel.allowsMultipleSelection); XCTAssertTrue(panel.treatsFilePackagesAsDirectories)
        var chosen = false, error = false
        let parent = ChatAttachmentPickerButton(enabled: true, onChoose: { _ in chosen = true }, onPresentation: { _ in }, onError: { error = true })
        let coordinator = ChatAttachmentPickerButton.Coordinator(parent)
        coordinator.pick(NSButton())
        XCTAssertFalse(chosen); XCTAssertTrue(error)
        coordinator.invalidate()
    }
}
