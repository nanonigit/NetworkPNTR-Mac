import Foundation
import XCTest
@testable import VMProbe

@MainActor final class EvidenceProbeReportTests: XCTestCase {
    private func ready() -> EvidenceExportProbe.Report {
        var value = EvidenceExportProbe.Report()
        value.expectedCPUCount = 1
        let files = EvidenceFixtureClient.expectedBodies.sorted(by: { $0.key < $1.key }).map { EvidenceFileProof(body: $0.key, byteCount: $0.value.size, sha256: $0.value.sha256) }
        value.boots = (1...2).map { .init(index: $0, cpuCount: 1, ready: true, credentialsAbsent: true, isolationWitnesses: true, formatObserved: $0 == 1, cooperativeStop: true, diagnostics: [], files: files) }
        value.logoutReceiptRejected = true; value.stopReceiptRejected = true; value.restartReceiptRejected = true
        value.noClobber = true; value.machineStopped = true; value.cleanupComplete = true
        return value
    }
    func testFailingFinalWriteCannotLeavePassingReportState() throws {
        var report = ready(), attemptedPassingWrite = false
        XCTAssertThrowsError(try report.publishFinal { value in
            attemptedPassingWrite = value.nativeProbePassed
            throw CocoaError(.fileWriteOutOfSpace)
        })
        XCTAssertTrue(attemptedPassingWrite); XCTAssertFalse(report.nativeProbePassed)
        XCTAssertEqual(report.stage, "final-report-failed")
        report.recordFailure(machineStopped: true, cleanupComplete: false)
        XCTAssertFalse(report.nativeProbePassed); XCTAssertFalse(report.cleanupComplete)
    }
    func testSuccessRequiresAllBootAndOwnershipProofs() throws {
        var report = ready(), didWrite = false
        try report.publishFinal { didWrite = $0.nativeProbePassed }
        XCTAssertTrue(didWrite); XCTAssertTrue(report.nativeProbePassed)
        for mode in 0..<5 {
            var incomplete = ready()
            if mode == 0 { incomplete.restartReceiptRejected = false }
            if mode == 1 { incomplete.boots.removeLast() }
            if mode == 2 { incomplete.expectedCPUCount = 2 }
            if mode == 3 { incomplete.cleanupComplete = false }
            if mode == 4 { incomplete.machineStopped = false }
            XCTAssertThrowsError(try incomplete.publishFinal { _ in XCTFail("Invalid proof was published") })
            XCTAssertFalse(incomplete.nativeProbePassed)
        }
    }
    func testStagingAuditChecksOwnedRootAndDownloadDirectoriesAndRejectsSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("artex-probe-staging-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertTrue(EvidenceProbeFile.stagingAbsent(root))
        let stage = root.appendingPathComponent(".artex-evidence-residue.partial")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        XCTAssertFalse(EvidenceProbeFile.stagingAbsent(root)); try FileManager.default.removeItem(at: stage)
        let downloads = root.appendingPathComponent("downloads-1")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: false)
        let nested = downloads.appendingPathComponent(".artex-evidence-residue.partial")
        try Data().write(to: nested)
        XCTAssertFalse(EvidenceProbeFile.stagingAbsent(root)); try FileManager.default.removeItem(at: nested)
        XCTAssertTrue(EvidenceProbeFile.stagingAbsent(root)); try FileManager.default.removeItem(at: downloads)
        try FileManager.default.createSymbolicLink(at: downloads, withDestinationURL: root)
        XCTAssertFalse(EvidenceProbeFile.stagingAbsent(root))
    }
}
