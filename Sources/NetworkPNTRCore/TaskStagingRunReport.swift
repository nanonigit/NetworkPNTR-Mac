import Foundation

public enum TaskStagingRunStage: String, Encodable, Sendable { case preparing, boot, authentication, transfer, shutdown, complete }

/// A completed transfer alone cannot turn a failed terminal path into a passing run.
public struct TaskStagingRunReport: Encodable, Sendable {
    public let stage: TaskStagingRunStage
    public let boot: BackendPreflightReport
    public let exercise: TaskStagingExerciseReport?
    public let terminalSuccess: Bool
    public let passed: Bool
    public init(stage: TaskStagingRunStage, boot: BackendPreflightReport, exercise: TaskStagingExerciseReport?, terminalSuccess: Bool) {
        self.stage = stage; self.boot = boot; self.exercise = exercise; self.terminalSuccess = terminalSuccess
        passed = terminalSuccess && stage == .complete && boot.passed && exercise != nil
    }
}
