import XCTest
@testable import NetworkPNTRCore

/// Actual wire shapes from checksum-bound SQL data; no response-derived expected assertions.
enum FindingExerciseTestData {
    static func objects() throws -> [[String:Any]] {
        let url = try XCTUnwrap(Bundle.module.url(forResource:"findings-runtime-seed",withExtension:"json",subdirectory:"Fixtures"))
        let seed = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
        let sources = try XCTUnwrap(seed["rows"] as? [[String:Any]])
        var rows: [[String:Any]] = []
        for source in sources {
            var row: [String:Any] = source
            let id = try XCTUnwrap(source["id"] as? Int)
            row["id"] = String(id)
            row["finding_id"] = String(id)
            row.removeValue(forKey:"node_id")
            row.removeValue(forKey:"asset_ids")
            if let task = source["task_id"] as? Int {
                row["task_id"] = String(task)
                row["task_description"] = "F4 terminal task \(task) \(FindingExerciseFixture.literal)"
            } else {
                row.removeValue(forKey:"task_id")
                row["task_description"] = ""
            }
            let ids = try XCTUnwrap(source["asset_ids"] as? [Int])
            var assets: [[String:String]] = []
            for assetID in ids { assets.append(try asset(assetID)) }
            row["assets"] = assets
            rows.append(row)
        }
        return rows
    }
    static func taskObjects(_ task: String,persisted: Bool = false) throws -> [[String:Any]] {
        var nodes: [[String:Any]] = []
        for var row in try objects() {
            let id = row["id"] as! String
            if persisted && ["9102","9133"].contains(id) { continue }
            guard row["task_id"] as? String != nil else { continue }
            if persisted && id == "9101" {
                row["name"] = FindingExerciseFixture.editedName; row["vulnclass"] = FindingExerciseFixture.editedClass
                row["severity"] = "low"; row["status"] = "fixed"
            }
            row["id"] = String(Int(id)!+6000)
            row["report"] = ""
            let evidence = try JSONSerialization.data(withJSONObject:row["evidence"]!,options:.fragmentsAllowed)
            row["evidence"] = String(data:evidence,encoding:.utf8)!
            nodes.append(row)
        }
        var own = nodes.filter{$0["task_id"] as? String == task}.reversed().map{$0}
        if task == "8111" {
            let encoded = try JSONSerialization.data(withJSONObject:FindingExerciseFixture.literal,options:.fragmentsAllowed)
            let legacy: [String:Any] = ["id":"15190","task_id":"8111", "task_description":"F4 terminal task 8111 \(FindingExerciseFixture.literal)",
                "name":"F4 legacy "+FindingExerciseFixture.literal,"vulnclass":"CWE-79","severity":"low","status":"pending",
                "summary":"Legacy without standalone handle","evidence":String(data:encoded,encoding:.utf8)!,"ts":"2026-10-22T10:00:59Z"]
            own.insert(legacy,at:0)
            for var row in nodes.reversed() where row["task_id"] as? String == "8101" {
                row["source_task_id"] = "8101"; row["inherited"] = true; own.append(row)
            }
        }
        return own
    }
    private static func asset(_ id: Int) throws -> [String:String] {
        let type: String
        let label: String
        switch id {
        case 8201: type = "root_domain"; label = "fixture.example.test"
        case 8202: type = "subdomain"; label = "api.fixture.example.test"
        case 8203: type = "ip"; label = "198.51.100.9"
        default: throw BackendAPIError.invalidResponse
        }
        return ["id":String(id),"type":type,"label":label]
    }
}
