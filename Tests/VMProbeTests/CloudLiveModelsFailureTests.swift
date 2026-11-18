import XCTest
@testable import VMProbe

final class CloudLiveModelsFailureTests: XCTestCase {
    #if DEBUG
    func testBackendFailureReportUsesOnlyFixedCategories() {
        XCTAssertEqual(CloudLiveModelsProbe.classifyBackendFailure("request: cloud egress configuration is not supported"), "vsock-configuration")
        XCTAssertEqual(CloudLiveModelsProbe.classifyBackendFailure("private-value: context deadline exceeded"), "deadline")
        XCTAssertEqual(CloudLiveModelsProbe.classifyBackendFailure("arbitrary private credential details"), "unclassified")
    }
    #endif
}
