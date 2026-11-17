import AppKit
import XCTest
@testable import NetworkPNTRCore
@testable import NetworkPNTRMac

final class ChatLocalizationControlTests: XCTestCase {
    @MainActor func testButtonAndEditorLanguageUpdatesPreserveOwnedControlAndTextSelection() {
        let button = NSButton(), editor = ChatComposer.Editor()
        editor.string = "literal **text** 日本語 中文 한국어"
        let selection = NSRange(location: 3, length: 4)
        editor.setSelectedRange(selection)
        for language in AppLanguage.allCases {
            ChatAttachmentPickerButton.applyLanguage(to: button, language: language)
            ChatComposer.applyLanguage(to: editor, language: language)
            XCTAssertEqual(button.title, AppStrings.text(.chatAttach, language: language))
            XCTAssertEqual(button.toolTip, button.title)
            XCTAssertEqual(button.accessibilityLabel(), button.title)
            XCTAssertEqual(editor.accessibilityLabel(), AppStrings.text(.chatMessage, language: language))
            XCTAssertEqual(editor.string, "literal **text** 日本語 中文 한국어")
            XCTAssertEqual(editor.selectedRange(), selection)
        }
    }
    @MainActor func testPanelLabelsUseChosenLanguageWithoutChangingSelectionPolicy() {
        for language in AppLanguage.allCases {
            let panel = ChatAttachmentPickerButton.makePanel(language: language)
            XCTAssertEqual(panel.prompt, AppStrings.text(.chatAttachPrompt, language: language))
            XCTAssertEqual(panel.message, AppStrings.text(.chatAttachMessage, language: language))
            XCTAssertTrue(panel.canChooseFiles); XCTAssertFalse(panel.canChooseDirectories)
            XCTAssertTrue(panel.allowsMultipleSelection)
        }
    }
    func testUploadProgressLanguageDoesNotChangeCountersOrClaimStorageAcceptance() {
        let progress = BackendUploadProgress(sentBodyBytes: 512, totalBodyBytes: 1024)
        let english = ChatUploadPresentation(progress: progress, language: .english)
        let japanese = ChatUploadPresentation(progress: progress, language: .japanese)
        XCTAssertEqual(english.title, "Uploading…")
        XCTAssertEqual(japanese.title, "アップロード中…")
        XCTAssertEqual(english.fraction, japanese.fraction)
        XCTAssertEqual(english.detail, japanese.detail)
        XCTAssertEqual(ChatUploadPresentation(progress: nil, language: .english).title, "Preparing files…")
        XCTAssertEqual(ChatUploadPresentation(progress: .init(sentBodyBytes: 1024, totalBodyBytes: 1024), language: .english).title, "Processing attachments…")
    }
}
