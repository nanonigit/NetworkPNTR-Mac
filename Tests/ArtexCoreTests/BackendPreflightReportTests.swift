import XCTest
@testable import ArtexCore
final class BackendPreflightReportTests: XCTestCase {
    private func report(log:String="",ready:Bool=true,stopped:Bool=true,status:Int?=401,isolation:Bool=true,credentials:Bool=true) -> BackendPreflightReport {
        let audit = GuestBootLogAudit(diagnostics:GuestBootDiagnostics.classify(log),credentialsAbsent:credentials,isolationWitnessesPresent:isolation,formatStageObserved:log.contains("ARTEX_MAC_STAGE_state_format"),complete:true)
        return .init(reachedReady:ready,freshAuth:true,protectedStatus:status,cooperativeStop:stopped,machineStopped:stopped,audit:audit)
    }
    func testPassRequiresAllReadinessAndShutdownEvidence() {
        XCTAssertTrue(report().passed); XCTAssertEqual(report().bootAttempts,1)
        XCTAssertFalse(report(ready:false).passed); XCTAssertFalse(report(stopped:false).passed); XCTAssertFalse(report(status:200).passed)
        XCTAssertFalse(report(isolation:false).passed)
        XCTAssertFalse(report(credentials:false).passed)
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
        let data = Data("network_hardware_devices=0\nnetwork_nonloopback_up=0\nnetwork_external_routes=0\nshared_mounts=0\nBad rss-counter state\nSegmentation fault\n".utf8) + Data(repeating:120,count:100_000)
        try data.write(to:root.appendingPathComponent("guest-fixture.log"))
        let tail = String(decoding:data.suffix(65536),as:UTF8.self)
        let limitedReport = report(log:tail)
        XCTAssertTrue(limitedReport.passed, "Negative control: display-tail evidence alone misses the fault")
        let audit = GuestBootDiagnostics.audit(logDirectory:root,tokens:["transport-fixture"])
        let completeReport = BackendPreflightReport(reachedReady:true,freshAuth:true,protectedStatus:401,cooperativeStop:true,machineStopped:true,audit:audit)
        XCTAssertTrue(audit.complete); XCTAssertTrue(audit.credentialsAbsent); XCTAssertTrue(audit.isolationWitnessesPresent)
        XCTAssertEqual(Set(audit.diagnostics),[.signalFault,.memoryAccountingFault])
        XCTAssertFalse(completeReport.passed, "A clean tail must not hide an earlier fault")
    }

}
