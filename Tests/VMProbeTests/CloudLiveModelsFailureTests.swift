import XCTest
@testable import VMProbe

final class CloudLiveModelsFailureTests: XCTestCase {
    #if DEBUG
    func testBackendFailureReportUsesOnlyFixedCategories() {
        XCTAssertEqual(CloudLiveModelsProbe.classifyBackendFailure("request: cloud egress configuration is not supported"), "vsock-configuration")
        XCTAssertEqual(CloudLiveModelsProbe.classifyBackendFailure("private-value: context deadline exceeded"), "deadline")
        XCTAssertEqual(CloudLiveModelsProbe.classifyBackendFailure("arbitrary private credential details"), "unclassified")
    }
    func testObservedGeminiInvalidArgumentKeyMessageIsRecognized() {
        let body = #"{"error":{"code":400,"status":"INVALID_ARGUMENT","message":"Please pass a valid API key"}}"#
        XCTAssertTrue(CloudLiveModelsProbe.rejectsGeminiKey(body[...]))
        let unrelated = #"{"error":{"code":400,"status":"INVALID_ARGUMENT","message":"Please pass a valid model"}}"#
        XCTAssertFalse(CloudLiveModelsProbe.rejectsGeminiKey(unrelated[...]))
        let wrongStatus = #"{"error":{"code":400,"status":"FAILED_PRECONDITION","message":"Please pass a valid API key"}}"#
        XCTAssertFalse(CloudLiveModelsProbe.rejectsGeminiKey(wrongStatus[...]))
    }
    #endif
}
