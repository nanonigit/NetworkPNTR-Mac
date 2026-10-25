import Foundation

public enum GuestBootDiagnostic: String, Codable, Hashable, Sendable {
    case kernelFault, signalFault, memoryAccountingFault, nonblankStateDisk, blankCheckFailure, otherGuestFailure
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

    /// Audit the complete owned, stopped-VM log, including secrets across chunk boundaries.
    public static func credentialsAbsent(logDirectory: URL, tokens: [String]) -> Bool {
        guard !tokens.isEmpty, tokens.count <= 16, tokens.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 8192 }) else { return false }
        do {
            let logs = try FileManager.default.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("guest-") && $0.pathExtension == "log" }
            guard logs.count == 1 else { return false }
            let properties = try logs[0].resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard properties.isRegularFile == true, properties.isSymbolicLink != true,
                  let size = properties.fileSize, size > 0, size <= 8 * 1024 * 1024 else { return false }
            let reader = try FileHandle(forReadingFrom: logs[0]); defer { try? reader.close() }
            let needles = tokens.map { Data($0.utf8) }; let overlap = (needles.map(\.count).max() ?? 1) - 1
            var tail = Data(); var total = 0
            while let chunk = try reader.read(upToCount: 65536), !chunk.isEmpty {
                total += chunk.count; guard total <= size else { return false }
                let window = tail + chunk
                if needles.contains(where: { window.range(of: $0) != nil }) { return false }
                tail = window.suffix(overlap)
            }
            let finalSize = try reader.seekToEnd()
            return total == size && finalSize == UInt64(size)
        } catch { return false }
    }
}

/// Fixed normalized evidence only. No raw log, error, token or filesystem path can be serialized.
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
    public let passed: Bool
    public init(reachedReady: Bool, freshAuth: Bool, protectedStatus: Int?, isolationVerified: Bool,
                credentialLogCheckPassed: Bool, cooperativeStop: Bool, machineStopped: Bool, guestLog: String, bootAttempts: Int = 1) {
        self.bootAttempts = bootAttempts
        self.reachedReady = reachedReady; self.freshAuth = freshAuth; self.protectedStatus = protectedStatus
        self.isolationVerified = isolationVerified; self.credentialLogCheckPassed = credentialLogCheckPassed
        self.cooperativeStop = cooperativeStop; self.machineStopped = machineStopped
        diagnostics = GuestBootDiagnostics.classify(guestLog)
        passed = bootAttempts == 1 && reachedReady && freshAuth && protectedStatus == 401 && isolationVerified && credentialLogCheckPassed && cooperativeStop && machineStopped && diagnostics.isEmpty
        formatStageObserved = guestLog.components(separatedBy: .newlines).contains("ARTEX_MAC_STAGE_state_format")
    }
}
