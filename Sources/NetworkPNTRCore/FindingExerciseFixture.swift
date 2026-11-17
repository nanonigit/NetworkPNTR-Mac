import Foundation

/// Independent Swift expectations for the fixed SQL seed; never creates or starts a task.
enum FindingExerciseFixture {
    struct Row: Sendable {
        let index: Int
        var name: String
        var vulnclass: String
        var severity: FindingSeverity
        var status: FindingStatus
        let summary: String
        let evidence: String
        let report: String
        let assetIDs: [String]
        var id: String { String(9101+index) }
        var nodeID: String? { index < 31 ? String(15101+index) : nil }
        var taskID: String? { index < 21 ? "8101" : (index < 31 ? String(8102+index-21) : nil) }
        var timestamp: String { String(format:"2026-10-22T10:00:%02dZ",index) }
        var taskDescription: String { taskID.map{"F4 terminal task \($0) \(FindingExerciseFixture.literal)"} ?? "" }
        var assets: [FindingAsset] {
            assetIDs.map { id in
                FindingAsset(id:id,type:id == "8201" ? "root_domain" : (id == "8202" ? "subdomain" : "ip"),
                             label:id == "8201" ? "fixture.example.test" : (id == "8202" ? "api.fixture.example.test" : "198.51.100.9"))
            }
        }
    }
    struct Vector: Sendable {
        let name: String
        let query: FindingQuery
        let ids: [String]
        let total: Int64
    }
    static let literal = "\u{feff}e\u{301} 中文 한국어 'quoted'"
    static let editedName = "F4 edited e\u{301} \u{feff} 中文 한국어 'quoted'"
    static let editedClass = "F4 edited class e\u{301}"
    static let failingName = "F4 NUL\0fixture"
    static let tasks = (8101...8111).map(String.init)
    static let scopes = ["c:8200","a:8201","a:8202","a:8203","__none__"]
    static let classes = ["CWE-79","CWE-89","F4 e\u{301} 中文 한국어"]
    static let severities: [FindingSeverity] = [.critical,.high,.medium,.low]
    static let statuses: [FindingStatus] = [.pending,.inProgress,.confirmed,.resolved,.fixed,.falsePositive,.ignored,.duplicate,.riskAccepted]
    static var initial: [Row] {
        (0..<33).map { index in
            Row(index:index,name:"F4 finding \(index+1) \(literal)",vulnclass:classes[index%3],severity:severities[index%4],status:statuses[index%9],
                summary:"F4 summary \(index+1) \(literal)",evidence:"F4 literal evidence \(index+1) \(literal)",report:"# F4 report \(index+1)\n\n\(literal)",
                assetIDs:index%5 == 0 ? [] : (index%5 == 1 ? ["8201","8202"] : [String(8201+index%3)]))
        }
    }
    static var persisted: [Row] {
        var rows = initial
        rows[0].name = editedName; rows[0].vulnclass = editedClass
        rows[0].severity = .low; rows[0].status = .fixed
        return rows.filter{!["9102","9133"].contains($0.id)}
    }
    static func sorted(_ rows: [Row],sort: FindingSort) -> [Row] {
        rows.sorted { a,b in
            if sort == .severity {
                let x = severities.firstIndex(of:a.severity) ?? 4, y = severities.firstIndex(of:b.severity) ?? 4
                if x != y { return x < y }
            }
            return a.index > b.index
        }
    }
    static func matching(_ rows: [Row],query: FindingQuery) -> [Row] {
        sorted(rows.filter { row in
            if let severity = query.severity, row.severity != severity { return false }
            if let status = query.status, row.status != status { return false }
            if !query.vulnclass.isEmpty, query.vulnclass != "all", !row.vulnclass.utf8.elementsEqual(query.vulnclass.utf8) { return false }
            if query.task == "__unassigned__", row.taskID != nil { return false }
            if query.task != "all", query.task != "__unassigned__", row.taskID != query.task { return false }
            if let scope = query.assetScope, !inScope(row,scope:scope) { return false }
            let term = asciiFold(ChatText.trim(query.search))
            if !term.isEmpty, ![row.name,row.vulnclass,row.summary,row.evidence,row.report].contains(where:{asciiFold($0).range(of:term) != nil}) { return false }
            return true
        },sort:query.sort)
    }
    static func inScope(_ row: Row,scope: String) -> Bool {
        switch scope {
        case "__none__": row.assetIDs.isEmpty
        case "c:8200": !row.assetIDs.isEmpty
        case "a:8201": row.assetIDs.contains("8201") || row.assetIDs.contains("8202")
        case "a:8202": row.assetIDs.contains("8202")
        case "a:8203": row.assetIDs.contains("8203")
        default: false
        }
    }
    static func vectors(rows: [Row]) -> [Vector] {
        var cases: [(String,FindingQuery)] = [
            ("flat_severity_1",.init()),("flat_severity_2",.init(page:2)),("flat_out_of_range",.init(page:3)),
            ("flat_time",.init(size:100,sort:.time))
        ]
        cases += severities.map{("severity_"+$0.rawValue,.init(size:100,severity:$0))}
        cases += statuses.map{("status_"+$0.rawValue,.init(size:100,status:$0))}
        cases += classes.enumerated().map{("class_\($0.offset)",.init(size:100,vulnclass:$0.element))}
        cases += (tasks+["__unassigned__"]).map{("task_"+$0,.init(size:100,task:$0))}
        for (name,term) in [("literal",literal),("report","F4 report 33"),("absent","F4 missing phrase"),("escaped","%_\\"),("NFC_absent","F4 é")] {
            cases.append(("search_"+name,.init(size:100,search:term)))
        }
        cases += scopes.enumerated().map{("asset_\($0.offset)",.init(size:100,assetScope:$0.element))}
        cases.append(("combined",.init(size:100,severity:.high,status:.inProgress,vulnclass:"CWE-89",task:"8101",search:"'quoted'",assetScope:"a:8201")))
        return cases.map { name,query in
            let found = matching(rows,query:query), start = Int(query.page-1)*query.size
            let page = start < found.count ? Array(found.dropFirst(start).prefix(query.size)) : []
            return Vector(name:name,query:query,ids:page.map(\.id),total:Int64(found.count))
        }
    }
    static func groups(rows: [Row],sort: FindingSort) -> [(String,[Row])] {
        let grouped = Dictionary(grouping:rows,by:{$0.taskID ?? "__unassigned__"})
        return grouped.map{($0.key,$0.value)}.sorted { a,b in
            if sort == .severity {
                let x = a.1.map{severities.firstIndex(of:$0.severity) ?? 4}.min() ?? 4
                let y = b.1.map{severities.firstIndex(of:$0.severity) ?? 4}.min() ?? 4
                if x != y { return x < y }
            }
            let x = a.1.map(\.index).max() ?? -1, y = b.1.map(\.index).max() ?? -1
            return x > y
        }
    }
    private static func asciiFold(_ text: String) -> Data { Data(text.utf8.map{(65...90).contains($0) ? $0+32 : $0}) }
}
