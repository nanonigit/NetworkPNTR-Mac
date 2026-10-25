import Foundation
import XCTest
@testable import ArtexCore

final class TaskUploadManifestTests: XCTestCase {
    private let draft = UUID(uuidString:"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private func attachment(_ name: String, _ size: Int64) throws -> TaskStagedAttachment {
        let data = try JSONSerialization.data(withJSONObject:["name":name,"path":"uploads/"+name,"size":size,"abs":"/state/app/data/drafts/"+draft.uuidString.lowercased()+"/uploads/"+name])
        let decoder = JSONDecoder(); decoder.userInfo[TaskStagedAttachment.draftKey] = draft
        return try decoder.decode(TaskStagedAttachment.self,from:data)
    }
    func testMatchesPinnedEnglishJapaneseAndRepeatedUpload() throws {
        let a = try attachment("\u{FEFF}e\u{301}日本.txt",1280)
        let bullet = "- " + a.absolutePath + " (1.3 KB)\n"
        for (language,marker,hint) in [(AppLanguage.english,"[Uploaded files (absolute paths)]","The worker can open these paths with Read/Bash:"),(.japanese,"【アップロードファイル(絶対パス)】","worker は Read/Bash でパスを開くことができます:")] {
            let result = TaskUploadManifest.appending(to:"\u{FEFF} original \n\u{FEFF}",attachments:[a],language:language)
            let expected = "\u{FEFF} original\n\n"+marker+" "+hint+"\n"+bullet
            XCTAssertTrue(result.utf8.elementsEqual(expected.utf8))
            let repeated = TaskUploadManifest.appending(to:result,attachments:[a],language:language)
            XCTAssertTrue(repeated.utf8.elementsEqual((expected+bullet).utf8))
            let b = try attachment("second.txt",0)
            let multi = TaskUploadManifest.appending(to:"\u{FEFF} original \n\u{FEFF}",attachments:[a,b],language:language)
            XCTAssertTrue(multi.utf8.elementsEqual((expected+"- "+b.absolutePath+" (0 B)\n").utf8))
            XCTAssertEqual(AppStrings.text(.taskUploadMarker,language:language),marker)
        }
    }
    func testWhitespaceByteMarkerAndLanguageSwitchMatchBrowser() throws {
        let a = try attachment("é.txt",0)
        let empty = TaskUploadManifest.appending(to:" \u{FEFF}\t",attachments:[a],language:.english)
        XCTAssertTrue(empty.hasPrefix("[Uploaded files (absolute paths)] "))
        let switched = TaskUploadManifest.appending(to:empty,attachments:[a],language:.japanese)
        XCTAssertTrue(switched.contains("\n\n【アップロードファイル(絶対パス)】 "))
        let marker = AppStrings.text(.taskUploadMarker,language:.japanese)
        let decomposed = marker.decomposedStringWithCanonicalMapping
        XCTAssertNotEqual(Data(marker.utf8),Data(decomposed.utf8))
        let result = TaskUploadManifest.appending(to:decomposed,attachments:[a],language:.japanese)
        XCTAssertTrue(result.contains("\n\n"+marker+" "))
        let nel = TaskUploadManifest.appending(to:"\u{85}",attachments:[a],language:.english)
        XCTAssertTrue(nel.hasPrefix("\u{85}\n\n"))
        XCTAssertEqual(TaskUploadManifest.appending(to:"literal",attachments:[],language:.english),"literal")
    }
    func testExactSizeRoundingAndBilingualUploadResources() throws {
        for (size,label) in [(Int64(0),"0 B"),(1023,"1023 B"),(1024,"1.0 KB"),(1280,"1.3 KB"),(1536,"1.5 KB"),(1048575,"1024.0 KB"),(1048576,"1.0 MB"),(1310720,"1.3 MB"),(134217728,"128.0 MB")] {
            let result = TaskUploadManifest.appending(to:"",attachments:[try attachment("f",size)],language:.english)
            XCTAssertTrue(result.hasSuffix(" ("+label+")\n"),"Size \(size)")
        }
        for key in AppStringKey.allCases where key.rawValue.hasPrefix("task.upload.") {
            for language in AppLanguage.allCases { XCTAssertNotEqual(AppStrings.text(key,language:language),key.rawValue) }
        }
    }
    func testAll126PinnedBrowserFunctionOracleCases() throws {
        struct Oracle: Decodable {
            struct Entry: Decodable {
                let language: String
                let description: String
                let attachment: TaskStagedAttachment
                let expected: String
            }
            let baseline: String
            let cases: [Entry]
        }
        let url = try XCTUnwrap(Bundle.module.url(forResource:"task-upload-manifest-oracle",withExtension:"json",subdirectory:"Fixtures"))
        let decoder = JSONDecoder(); decoder.userInfo[TaskStagedAttachment.draftKey] = draft
        let oracle = try decoder.decode(Oracle.self,from:Data(contentsOf:url))
        XCTAssertEqual(oracle.baseline,"e75ae371ad777ffd1eecdd28d2781a6519b05591"); XCTAssertEqual(oracle.cases.count,126)
        for entry in oracle.cases {
            let value = TaskUploadManifest.appending(to:entry.description,attachments:[entry.attachment],language:entry.language == "en" ? .english : .japanese)
            XCTAssertTrue(value.utf8.elementsEqual(entry.expected.utf8),"Mismatch \(entry.language) size \(entry.attachment.size)")
        }
    }
}
