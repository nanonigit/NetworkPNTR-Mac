import XCTest
@testable import ArtexCore

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
