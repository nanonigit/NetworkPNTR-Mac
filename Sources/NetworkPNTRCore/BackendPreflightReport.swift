import Foundation

public enum GuestBootDiagnostic: String, Codable, Hashable, Sendable {
    case kernelFault, signalFault, memoryAccountingFault, nonblankStateDisk, blankCheckFailure, otherGuestFailure, logAuditFailure
}

public enum GuestBootDiagnostics {
    public static func classify(_ log: String) -> [GuestBootDiagnostic] {
        var found: [GuestBootDiagnostic] = []
        if log.contains("Kernel panic") || log.contains("Internal error: Oops") { found.append(.kernelFault) }
        let lower = log.lowercased()
        if ["sigsegv", "sigbus", "sigill", "segmentation fault"].contains(where: lower.contains) { found.append(.signalFault) }
        if log.contains("Bad rss-counter state") || log.contains("non-zero pgtables_bytes") { found.append(.memoryAccountingFault) }
        let failures = log.components(separatedBy: .newlines).filter { $0.hasPrefix("ARTEX_MAC_GUEST_ERROR stage=") }
        let nonblank = "ARTEX_MAC_GUEST_ERROR stage=nonblank-state-disk"
        let checker = "ARTEX_MAC_GUEST_ERROR stage=state-blank-check-failed"
        if failures.contains(nonblank) { found.append(.nonblankStateDisk) }
        if failures.contains(checker) { found.append(.blankCheckFailure) }
        if failures.contains(where: { $0 != nonblank && $0 != checker }) { found.append(.otherGuestFailure) }
        return found
    }

    public static func credentialsAbsent(logDirectory: URL, tokens: [String]) -> Bool {
        audit(logDirectory: logDirectory, tokens: tokens).credentialsAbsent
    }

    /// One complete, bounded stopped-VM log snapshot supplies every log-based verdict.
    public static func audit(logDirectory: URL, tokens: [String]) -> GuestBootLogAudit {
        guard !tokens.isEmpty, tokens.count <= 16, tokens.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 8192 }) else { return .unavailable }
        do {
            let logs = try FileManager.default.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("guest-") && $0.pathExtension == "log" }
            guard logs.count == 1 else { return .unavailable }
            let properties = try logs[0].resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard properties.isRegularFile == true, properties.isSymbolicLink != true,
                  let size = properties.fileSize, size > 0, size <= 8 * 1024 * 1024 else { return .unavailable }
            let reader = try FileHandle(forReadingFrom: logs[0]); defer { try? reader.close() }
            var snapshot = Data()
            while let chunk = try reader.read(upToCount: 65536), !chunk.isEmpty {
                guard chunk.count <= size - snapshot.count else { return .unavailable }
                snapshot.append(chunk)
            }
            let finalSize = try reader.seekToEnd()
            guard snapshot.count == size, finalSize == UInt64(size) else { return .unavailable }
            let log = String(decoding: snapshot, as: UTF8.self)
            let lines = Set(log.components(separatedBy: .newlines))
            let witnesses = ["network_hardware_devices=0", "network_nonloopback_up=0", "network_external_routes=0", "shared_mounts=0"]
            return GuestBootLogAudit(diagnostics: classify(log), credentialsAbsent: !tokens.contains { snapshot.range(of: Data($0.utf8)) != nil },
                                    isolationWitnessesPresent: witnesses.allSatisfy(lines.contains),
                                    formatStageObserved: lines.contains("ARTEX_MAC_STAGE_state_format"), complete: true)
        } catch { return .unavailable }
    }

}

/// Contains no raw log or tokens. Only the Core audit can construct production values.
public struct GuestBootLogAudit: Sendable {
    public let diagnostics: [GuestBootDiagnostic]
    public let credentialsAbsent: Bool
    public let isolationWitnessesPresent: Bool
    public let formatStageObserved: Bool
    public let complete: Bool
    static var unavailable: Self { .init(diagnostics: [.logAuditFailure], credentialsAbsent: false, isolationWitnessesPresent: false, formatStageObserved: false, complete: false) }
}

/// Fixed normalized evidence only. Display-tail text is deliberately not an input.
public struct BackendPreflightReport: Encodable, Sendable {
    public let bootAttempts: Int
    public let reachedReady: Bool
    public let freshAuth: Bool
    public let protectedStatus: Int?
    public let isolationVerified: Bool
    public let credentialLogCheckPassed: Bool
    public let cooperativeStop: Bool
    public let machineStopped: Bool
    public let diagnostics: [GuestBootDiagnostic]
    public let formatStageObserved: Bool
    public let logAuditComplete: Bool
    public let supplementalEvidenceComplete: Bool
    public let passed: Bool
    public init(reachedReady: Bool, freshAuth: Bool, protectedStatus: Int?, cooperativeStop: Bool,
                machineStopped: Bool, audit: GuestBootLogAudit, bootAttempts: Int = 1, supplementalEvidenceComplete: Bool = true) {
        self.bootAttempts = bootAttempts
        self.reachedReady = reachedReady; self.freshAuth = freshAuth; self.protectedStatus = protectedStatus
        isolationVerified = audit.isolationWitnessesPresent; credentialLogCheckPassed = audit.credentialsAbsent
        self.cooperativeStop = cooperativeStop; self.machineStopped = machineStopped
        diagnostics = audit.diagnostics; formatStageObserved = audit.formatStageObserved; logAuditComplete = audit.complete
        self.supplementalEvidenceComplete = supplementalEvidenceComplete
        passed = supplementalEvidenceComplete && bootAttempts == 1 && reachedReady && freshAuth && protectedStatus == 401 && isolationVerified && credentialLogCheckPassed && cooperativeStop && machineStopped && logAuditComplete && diagnostics.isEmpty
    }
}
