import Foundation
import XCTest
@testable import NetworkPNTRCore

private final class ProgressValues: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [BackendUploadProgress] = []
    func append(_ value: BackendUploadProgress) { lock.lock(); storage.append(value); lock.unlock() }
    var values: [BackendUploadProgress] { lock.lock(); defer { lock.unlock() }; return storage }
}
final class BackendUploadProgressTests: XCTestCase {
    func testFirstThrottledAndFinalBodyWritesHaveMonotonicExactCounters() throws {
        let values = ProgressValues(), start = ContinuousClock.now
        let reporter = try BackendUploadProgressReporter(totalBodyBytes: 1000, progress: { values.append($0) })
        try reporter.record(sentBodyBytes: 0, now: start)
        try reporter.record(sentBodyBytes: 10, now: start)
        try reporter.record(sentBodyBytes: 20, now: start.advanced(by: .milliseconds(10)))
        try reporter.record(sentBodyBytes: 200, now: start.advanced(by: .milliseconds(50)))
        try reporter.record(sentBodyBytes: 1000, now: start.advanced(by: .milliseconds(51)))
        try reporter.record(sentBodyBytes: 1000, now: start.advanced(by: .milliseconds(200)))
        XCTAssertEqual(values.values.map(\.sentBodyBytes), [10,200,1000])
        XCTAssertTrue(values.values.allSatisfy { $0.totalBodyBytes == 1000 })
    }
    func testInvalidAndRegressingBodyCountsFailIncludingThrottledObservations() throws {
        XCTAssertThrowsError(try BackendUploadProgressReporter(totalBodyBytes: 0, progress: nil))
        let reporter = try BackendUploadProgressReporter(totalBodyBytes: 100, progress: nil)
        try reporter.record(sentBodyBytes: 20)
        try reporter.record(sentBodyBytes: 30)
        for count: Int64 in [-1,29,101] { XCTAssertThrowsError(try reporter.record(sentBodyBytes: count)) }
    }
    func testClosedDeliveryGateRejectsLateCallbacks() {
        let values = ProgressValues()
        let gate = BackendUploadProgressGate { values.append($0) }
        let event = BackendUploadProgress(sentBodyBytes: 1, totalBodyBytes: 10)
        gate.receive(event); gate.close(); gate.receive(event); gate.close()
        XCTAssertEqual(values.values.count, 1)
    }
}
