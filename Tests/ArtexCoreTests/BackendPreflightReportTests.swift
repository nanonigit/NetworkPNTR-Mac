import XCTest
@testable import ArtexCore
final class BackendPreflightReportTests: XCTestCase {
    private func report(log:String="",ready:Bool=true,stopped:Bool=true,status:Int?=401) -> BackendPreflightReport {
        .init(reachedReady:ready,freshAuth:true,protectedStatus:status,isolationVerified:true,credentialLogCheckPassed:true,cooperativeStop:stopped,machineStopped:stopped,guestLog:log)
    }
    func testPassRequiresAllReadinessAndShutdownEvidence() {
        XCTAssertTrue(report().passed); XCTAssertEqual(report().bootAttempts,1)
        XCTAssertFalse(report(ready:false).passed); XCTAssertFalse(report(stopped:false).passed); XCTAssertFalse(report(status:200).passed)
        XCTAssertFalse(BackendPreflightReport(reachedReady:true,freshAuth:true,protectedStatus:401,isolationVerified:false,credentialLogCheckPassed:true,cooperativeStop:true,machineStopped:true,guestLog:"").passed)
        XCTAssertFalse(BackendPreflightReport(reachedReady:true,freshAuth:true,protectedStatus:401,isolationVerified:true,credentialLogCheckPassed:false,cooperativeStop:true,machineStopped:true,guestLog:"").passed)
    }
    func testClassificationRetainsOldAmbiguityAndSeparatesExecutionFailure() {
        let old = report(log:"ARTEX_MAC_GUEST_ERROR stage=nonblank-state-disk\nSegmentation fault\nBad rss-counter state")
        XCTAssertEqual(Set(old.diagnostics),[.nonblankStateDisk,.signalFault,.memoryAccountingFault]); XCTAssertFalse(old.passed)
        let fixed = report(log:"ARTEX_MAC_GUEST_ERROR stage=state-blank-check-failed")
        XCTAssertEqual(fixed.diagnostics,[.blankCheckFailure]); XCTAssertFalse(fixed.formatStageObserved)
        XCTAssertEqual(report(log:"Kernel panic\nInternal error: Oops").diagnostics,[.kernelFault])
        XCTAssertTrue(report(log:"ARTEX_MAC_STAGE_state_format").formatStageObserved)
    }
    func testUntrustedLogStringsNeverEnterSerializedReport() throws {
        let item = report(log:"private-secret /Users/private\nARTEX_MAC_GUEST_ERROR stage=private-secret\n")
        XCTAssertEqual(item.diagnostics,[.otherGuestFailure]); XCTAssertFalse(item.passed)
        let data = try JSONEncoder().encode(item); let text = String(decoding:data,as:UTF8.self)
        XCTAssertFalse(text.contains("private-secret")); XCTAssertFalse(text.contains("/Users")); XCTAssertFalse(text.contains("guestLog"))
    }
    func testProvisioningSecretAuditScansWholePrivateLogAndRejectsAmbiguity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false)
        defer { try? FileManager.default.removeItem(at:root) }
        let log = root.appendingPathComponent("guest-fixture.log"); let tokens = ["transport-private-fixture", "setup-private-fixture"]
        try Data("clean boot".utf8).write(to:log)
        XCTAssertTrue(GuestBootDiagnostics.credentialsAbsent(logDirectory:root,tokens:tokens))
        try (Data(repeating:120,count:65530) + Data(tokens[0].utf8) + Data(repeating:121,count:100_000)).write(to:log)
        XCTAssertFalse(GuestBootDiagnostics.credentialsAbsent(logDirectory:root,tokens:tokens))
        try Data("clean boot".utf8).write(to:log)
        XCTAssertFalse(GuestBootDiagnostics.credentialsAbsent(logDirectory:root,tokens:[]))
        try Data("other boot".utf8).write(to:root.appendingPathComponent("guest-other.log"))
        XCTAssertFalse(GuestBootDiagnostics.credentialsAbsent(logDirectory:root,tokens:tokens))
    }

    func testEarlyFaultCannotDisappearBehindLongCleanTail() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false)
        defer { try? FileManager.default.removeItem(at:root) }
        let data = Data("Bad rss-counter state\nSegmentation fault\n".utf8) + Data(repeating:120,count:100_000)
        try data.write(to:root.appendingPathComponent("guest-fixture.log"))
        let tail = String(decoding:data.suffix(65536),as:UTF8.self)
        let limitedReport = report(log:tail)
        let tokenAudit = GuestBootDiagnostics.credentialsAbsent(logDirectory:root,tokens:["transport-fixture"])
        XCTAssertFalse(limitedReport.passed && tokenAudit, "A clean tail must not hide an earlier fault")
    }

}
