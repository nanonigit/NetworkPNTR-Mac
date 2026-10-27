import Foundation

/// Independent fixture aggregation; never derives expected counts from the response being checked.
enum FindingExerciseAggregateVerifier {
    typealias Row = FindingExerciseFixture.Row
    static func stats(_ actual: FindingStats,rows: [Row]) throws {
        let classes = Set(rows.map{Data($0.vulnclass.utf8)}).sorted{$0.lexicographicallyPrecedes($1)}
        let tasks = FindingExerciseFixture.groups(rows:rows,sort:.time).filter{$0.0 != "__unassigned__"}
        guard actual.total == Int64(rows.count), actual.pending == Int64(rows.filter{$0.status == .pending}.count),
              counts(actual.critical,actual.high,actual.medium,actual.low,rows:rows),
              actual.vulnclasses.map({Data($0.utf8)}) == classes, actual.tasks.map(\.id) == tasks.map(\.0) else { throw failure() }
        for (value,expected) in zip(actual.tasks,tasks) {
            guard value.count == Int64(expected.1.count), same(value.name,taskName(expected.0)),
                  same(value.description,taskDescription(expected.0)) else { throw failure() }
        }
    }
    static func groups(_ actual: FindingGroupsPage,query: FindingQuery,rows: [Row]) throws {
        let filtered = FindingExerciseFixture.matching(rows,query:query)
        let groups = FindingExerciseFixture.groups(rows:filtered,sort:query.sort)
        let offset = Int(query.page-1)*query.size
        let page = Array(groups.dropFirst(offset).prefix(query.size))
        guard actual.total == Int64(groups.count), actual.findingTotal == Int64(filtered.count), actual.page == query.page,
              actual.pageSize == query.size, actual.items.map({$0.taskId ?? "__unassigned__"}) == page.map(\.0) else { throw failure() }
        for (value,expected) in zip(actual.items,page) {
            guard value.count == Int64(expected.1.count), counts(value.critical,value.high,value.medium,value.low,rows:expected.1),
                  value.lastFoundAt == timestamp(expected.1), same(value.taskName,taskName(expected.0)),
                  same(value.taskDescription,taskDescription(expected.0)),
                  value.taskStatus == (expected.0 == "__unassigned__" ? "" : "done") else { throw failure() }
        }
    }
    private struct Node {
        let key: String, parent: String?, kind: String, label: String
        let asset: Int64?, company: Int64?
        let rows: [Row]
        let direct: Int64
    }
    static func tree(_ actual: FindingAssetTree,rows: [Row]) throws {
        var expected: [Node] = []
        for key in FindingExerciseFixture.scopes {
            let found = rows.filter{FindingExerciseFixture.inScope($0,scope:key)}
            guard !found.isEmpty else { continue }
            let node = node(key,rows:found,all:rows)
            expected.append(node)
        }
        expected.sort { a,b in
            if (a.kind == "none") != (b.kind == "none") { return b.kind == "none" }
            if a.rows.count != b.rows.count { return a.rows.count > b.rows.count }
            return a.label.utf8.lexicographicallyPrecedes(b.label.utf8)
        }
        guard actual.findingTotal == Int64(rows.count), !actual.truncated, actual.droppedKinds.isEmpty,
              actual.nodes.map(\.key) == expected.map(\.key) else { throw failure() }
        for (value,node) in zip(actual.nodes,expected) {
            guard value.parent == node.parent, value.kind == node.kind, same(value.label,node.label),
                  value.assetId == node.asset, value.companyId == node.company, value.selfCount == node.direct,
                  value.total == Int64(node.rows.count), counts(value.critical,value.high,value.medium,value.low,rows:node.rows),
                  value.lastFoundAt == timestamp(node.rows) else { throw failure() }
        }
    }
    private static func node(_ key: String,rows: [Row],all: [Row]) -> Node {
        let parent: String?, kind: String, label: String, asset: Int64?, company: Int64?
        switch key {
        case "c:8200":
            parent = nil; kind = "company"; label = "F4 company "+FindingExerciseFixture.literal; asset = nil; company = 8200
        case "a:8201":
            parent = "c:8200"; kind = "root_domain"; label = "fixture.example.test"; asset = 8201; company = 8200
        case "a:8202":
            parent = "a:8201"; kind = "subdomain"; label = "api.fixture.example.test"; asset = 8202; company = 8200
        case "a:8203":
            parent = "c:8200"; kind = "ip"; label = "198.51.100.9"; asset = 8203; company = 8200
        default:
            parent = nil; kind = "none"; label = "未关联资产"; asset = nil; company = nil
        }
        let direct: Int
        if let asset { direct = all.filter{$0.assetIDs.contains(String(asset))}.count }
        else { direct = kind == "none" ? rows.count : 0 }
        return Node(key:key,parent:parent,kind:kind,label:label,asset:asset,company:company,rows:rows,direct:Int64(direct))
    }
    private static func counts(_ critical: Int64,_ high: Int64,_ medium: Int64,_ low: Int64,rows: [Row]) -> Bool {
        let expected = FindingExerciseFixture.severities.map{level in Int64(rows.filter{$0.severity == level}.count)}
        return [critical,high,medium,low] == expected
    }
    private static func timestamp(_ rows: [Row]) -> String { rows.max(by:{$0.index < $1.index})?.timestamp ?? "" }
    private static func taskName(_ id: String) -> String { id == "__unassigned__" ? "" : "F4 task \(id) \(FindingExerciseFixture.literal)" }
    private static func taskDescription(_ id: String) -> String { id == "__unassigned__" ? "" : "F4 terminal task \(id) \(FindingExerciseFixture.literal)" }
    private static func same(_ a: String,_ b: String) -> Bool { a.utf8.elementsEqual(b.utf8) }
    private static func failure() -> RuntimeError { .integrity("findings exercise aggregate mismatch") }
}
