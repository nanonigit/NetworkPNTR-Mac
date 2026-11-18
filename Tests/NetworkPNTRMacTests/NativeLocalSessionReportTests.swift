import Foundation
import XCTest
@testable import NetworkPNTRMac

final class NativeLocalSessionReportTests: XCTestCase {
    #if DEBUG
    func testReceiptWriteFailureIsPropagated() {
        struct WriteFailure: Error {}
        XCTAssertThrowsError(try NativeLocalSessionReport.publish(["complete": true], at: URL(fileURLWithPath: "/unused"), write: { _, _ in
            throw WriteFailure()
        })) { XCTAssertTrue($0 is WriteFailure) }
    }
    func testReceiptCannotReportSuccessBeforeActualWrite() throws {
        var written = false
        try NativeLocalSessionReport.publish(["complete": false, "failedPhase": "startup"], at: URL(fileURLWithPath: "/unused"), write: { data, _ in
            let record = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(record["complete"] as? Bool, false)
            XCTAssertEqual(record["failedPhase"] as? String, "startup")
            written = true
        })
        XCTAssertTrue(written)
    }
    #endif
}
