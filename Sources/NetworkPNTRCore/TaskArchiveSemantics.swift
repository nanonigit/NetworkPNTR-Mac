/// Source-coded state and phase presentation. Unknown values never become owned UI text.
public enum TaskArchiveSemantics {
    private static let stateKeys: [String:AppStringKey] = [
        "archive_queued":.taskArchiveStateArchiveQueued,
        "archiving":.taskArchiveStateArchiving,
        "archive_failed":.taskArchiveStateArchiveFailed,
        "ready":.taskArchiveStateReady,
        "restore_queued":.taskArchiveStateRestoreQueued,
        "restoring":.taskArchiveStateRestoring,
        "restore_failed":.taskArchiveStateRestoreFailed,
        "delete_queued":.taskArchiveStateDeleteQueued,
        "deleting":.taskArchiveStateDeleting,
        "delete_failed":.taskArchiveStateDeleteFailed
    ]
    private static let phaseKeys: [String:AppStringKey] = [
        "queued":.taskArchivePhaseQueued,
        "starting":.taskArchivePhaseStarting,
        "interrupted":.taskArchivePhaseInterrupted,
        "failed":.taskArchivePhaseFailed,
        "stage_files":.taskArchivePhaseStageFiles,
        "snapshot_database":.taskArchivePhaseSnapshotDatabase,
        "snapshot_traffic":.taskArchivePhaseSnapshotTraffic,
        "compress":.taskArchivePhaseCompress,
        "compact_traffic":.taskArchivePhaseCompactTraffic,
        "compact_database":.taskArchivePhaseCompactDatabase,
        "verify_package":.taskArchivePhaseVerifyPackage,
        "restore_traffic":.taskArchivePhaseRestoreTraffic,
        "restore_files":.taskArchivePhaseRestoreFiles,
        "restore_database":.taskArchivePhaseRestoreDatabase,
        "consume_package":.taskArchivePhaseConsumePackage,
        "stage_package_delete":.taskArchivePhaseStagePackageDelete,
        "delete_metadata":.taskArchivePhaseDeleteMetadata,
        "ready":.taskArchivePhaseReady,
        "database_restored":.taskArchivePhaseDatabaseRestored
    ]
    public static let states = ["archive_queued", "archiving", "archive_failed", "ready", "restore_queued", "restoring", "restore_failed", "delete_queued", "deleting", "delete_failed"]
    public static let phases = ["queued", "starting", "interrupted", "failed", "stage_files", "snapshot_database", "snapshot_traffic", "compress", "compact_traffic", "compact_database", "verify_package", "restore_traffic", "restore_files", "restore_database", "consume_package", "stage_package_delete", "delete_metadata", "ready", "database_restored"]
    public static func stateKey(_ value: String) -> AppStringKey { stateKeys[value] ?? .taskArchiveUnknownState }
    public static func phaseKey(_ value: String) -> AppStringKey { phaseKeys[value] ?? .taskArchiveUnknownPhase }
    public static func processing(_ state: String) -> Bool {
        ["archive_queued","archiving","restore_queued","restoring","delete_queued","deleting"].contains(state)
    }
    public static func canRestore(_ row: TaskArchiveRecord) -> Bool { ["ready","restore_failed"].contains(row.state) }
    public static func canDelete(_ row: TaskArchiveRecord) -> Bool { ["ready","delete_failed"].contains(row.state) }
    public static func canRetry(_ row: TaskArchiveRecord) -> Bool { ["archive_failed","restore_failed","delete_failed"].contains(row.state) }
    public static func supportedFormat(_ row: TaskArchiveRecord) -> Bool { (1...3).contains(row.formatVersion) }
    public static func canArchive(_ row: TaskRecord, batch: Bool = false) -> Bool {
        guard ["paused","done","failed","timeout"].contains(row.status), !row.queued else { return false }
        return batch || row.archiveBlockedByTaskId == nil || row.archiveBlockedByTaskId == ""
    }
}
