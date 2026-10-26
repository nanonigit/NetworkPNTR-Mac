import ArtexCore
import Foundation

enum TaskArchivePresentation {
    static func pages(total: Int64, size: Int) -> Int64 { total > 0 && size > 0 ? (total-1)/Int64(size)+1 : 1 }
    static func title(_ row: TaskArchiveRecord, language: AppLanguage) -> String {
        if !row.taskName.isEmpty { return row.taskName }
        if !row.taskDescription.isEmpty { return row.taskDescription }
        return AppStrings.formatted(.taskUIUnnamed,language:language,values:["id":String(row.taskId)])
    }
    static func originalStatus(_ row: TaskArchiveRecord, language: AppLanguage) -> String {
        TaskPresentation.statuses.contains(row.originalStatus) ? DashboardLabels.text(row.originalStatus,domain:.task,language:language) : AppStrings.text(.taskArchiveUIOriginalUnknown,language:language)
    }
    static func dataTotal(_ rows: [TaskArchiveRecord]) -> Decimal { rows.reduce(Decimal.zero) { sum,row in row.dataCounts.values.reduce(sum){$0+Decimal($1)} } }
    static func compressedTotal(_ rows: [TaskArchiveRecord]) -> Decimal { rows.reduce(Decimal.zero){$0+Decimal($1.compressedSize)} }
    static func number(_ value: Decimal, language: AppLanguage, fraction: Int = 0) -> String {
        let f = NumberFormatter(); f.locale = language.locale; f.numberStyle = .decimal; f.maximumFractionDigits = fraction; f.roundingMode = .halfUp
        return f.string(from:NSDecimalNumber(decimal:value)) ?? NSDecimalNumber(decimal:value).stringValue
    }
    static func bytes(_ value: Decimal, language: AppLanguage) -> String {
        let units = ["B","KiB","MiB","GiB","TiB","PiB","EiB","ZiB","YiB"]
        var scaled = max(0,value), index = 0
        while scaled >= 1024, index < units.count-1 { scaled /= 1024; index += 1 }
        return number(scaled,language:language,fraction:index == 0 ? 0 : 1)+" "+units[index]
    }
    static func compression(_ row: TaskArchiveRecord, language: AppLanguage) -> String {
        guard row.originalSize > 0, row.compressedSize > 0 else { return "—" }
        let percent = max(0,(1-Decimal(row.compressedSize)/Decimal(row.originalSize))*100)
        return AppStrings.formatted(.taskArchiveUICompression,language:language,values:["size":bytes(Decimal(row.compressedSize),language:language),"percent":number(percent,language:language)])
    }
    static func actionKey(_ kind: TaskArchiveActionKind) -> AppStringKey {
        switch kind { case .archive: .taskArchiveUIArchive; case .restore: .taskArchiveUIRestore; case .delete: .taskArchiveUIDelete; case .retry: .taskArchiveUIRetry }
    }
    static func helpKey(_ kind: TaskArchiveActionKind) -> AppStringKey {
        switch kind { case .archive: .taskArchiveUIArchiveHelp; case .restore: .taskArchiveUIRestoreHelp; case .delete: .taskArchiveUIDeleteHelp; case .retry: .taskArchiveUIRetryHelp }
    }
    static func outcomeKey(_ value: TaskArchiveActionItem.State) -> AppStringKey {
        switch value { case .accepted: .taskArchiveUIAccepted; case .rejected: .taskBulkRejected; case .unconfirmed: .taskBulkUnconfirmed; case .notStarted: .taskBulkNotStarted }
    }
}
