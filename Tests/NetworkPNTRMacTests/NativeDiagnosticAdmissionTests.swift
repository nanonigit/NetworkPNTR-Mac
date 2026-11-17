import XCTest
@testable import NetworkPNTRMac

final class NativeDiagnosticAdmissionTests: XCTestCase {
    #if DEBUG
    func testRuntimeAttachesAfterLaunchWithoutLosingRequest() {
        var admission = NativeDiagnosticAdmission()
        admission.didLaunch()
        XCTAssertFalse(admission.admit(requested: true, hasEnvironment: false))
        XCTAssertFalse(admission.started)
        XCTAssertTrue(admission.admit(requested: true, hasEnvironment: true))
        XCTAssertFalse(admission.admit(requested: true, hasEnvironment: true))
    }

    func testRuntimeAttachesBeforeLaunchAndStartsOnlyOnce() {
        var admission = NativeDiagnosticAdmission()
        XCTAssertFalse(admission.admit(requested: true, hasEnvironment: true))
        admission.didLaunch()
        XCTAssertTrue(admission.admit(requested: true, hasEnvironment: true))
        admission.didLaunch()
        XCTAssertFalse(admission.admit(requested: true, hasEnvironment: true))
    }

    func testNormalLaunchNeverStartsDiagnostics() {
        var admission = NativeDiagnosticAdmission()
        admission.didLaunch()
        XCTAssertFalse(admission.admit(requested: false, hasEnvironment: true))
        XCTAssertFalse(admission.started)
    }
    #endif
}
