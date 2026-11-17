import Foundation
import XCTest
@testable import NetworkPNTRCore
@testable import VMProbe

final class CapturedProbeContractTests: XCTestCase {
    func testFixedBodiesAndURLOrdinalsPreserveBytes() throws {
        XCTAssertEqual(try CapturedProbeContract.bytes(0,side:.response).count,0)
        XCTAssertEqual(try CapturedProbeContract.bytes(3,side:.response).count,9003)
        XCTAssertEqual(try CapturedProbeContract.bytes(4,side:.response).count,262401)
        XCTAssertEqual(ArtifactIntegrity.sha256(try CapturedProbeContract.bytes(1,side:.response)),"e34ddc517f3d74c938352c489e37a79bd855818916bfbce320c03115d6a35224")
        XCTAssertEqual(try CapturedProbeContract.ordinal("http://127.0.0.1:8799/f5-captured/04"),4)
        for url in ["https://127.0.0.1:8799/f5-captured/04","http://127.0.0.1:8799/f5-captured/4","http://127.0.0.1:8799/f5-captured/29"] { XCTAssertThrowsError(try CapturedProbeContract.ordinal(url)) }
        XCTAssertThrowsError(try CapturedProbeContract.bytes(-1,side:.request))
    }
    private func preview(content: String,offset: Int64,total: Int64,next: Int64,binary: Bool,truncated: Bool) throws -> FindingEvidencePreview {
        try BackendJSONCoding.decode(FindingEvidencePreview.self,from:JSONSerialization.data(withJSONObject:["content":content,"offset":offset,"total":total,"next_offset":next,"binary":binary,"truncated":truncated]))
    }
    func testPreviewOracleChecksExactSplitUTF8BinaryAndEmpty() throws {
        let data=try CapturedProbeContract.bytes(3,side:.response)
        let first=try preview(content:String(decoding:data.prefix(8191),as:UTF8.self),offset:0,total:9003,next:8191,binary:false,truncated:true)
        _ = try CapturedProbeContract.validate(first,data:data,offset:0)
        let tail=try preview(content:String(decoding:data.dropFirst(8191),as:UTF8.self),offset:8191,total:9003,next:9003,binary:false,truncated:false)
        _ = try CapturedProbeContract.validate(tail,data:data,offset:8191)
        let binary=try CapturedProbeContract.bytes(4,side:.response)
        _ = try CapturedProbeContract.validate(preview(content:"[二进制正文，262401 字节；请下载查看]",offset:0,total:262401,next:8192,binary:true,truncated:true),data:binary,offset:0)
        _ = try CapturedProbeContract.validate(preview(content:"",offset:0,total:0,next:0,binary:false,truncated:false),data:Data(),offset:0)
        XCTAssertThrowsError(try CapturedProbeContract.validate(first,data:data,offset:8191))
        let changed=try preview(content:"changed",offset:0,total:9003,next:8191,binary:false,truncated:true)
        XCTAssertThrowsError(try CapturedProbeContract.validate(changed,data:data,offset:0))
    }
    func testEmptyReconciliationSummaryFailsBeforeBindingAccess() throws {
        let empty=try BackendJSONCoding.decode(FindingTraffic.self,from:Data(#"{"finding_id":"9101","version":2,"report_version":0,"bindings":[]}"#.utf8))
        XCTAssertThrowsError(try CapturedProbeContract.editedBinding(empty,first:"1",second:"2"))
    }
    func testFinalGateRequiresTwoCleanBootsComparisonAndRecovery() throws {
        let complete=CapturedProbeContract.Completion(boots:2,cooperativeStops:2,cleanAudits:2,sourceVerified:true,referenceEqual:true,persistence:true,uncertaintyRecovered:true,machineStopped:true)
        XCTAssertNoThrow(try complete.validate())
        let values=[CapturedProbeContract.Completion(boots:1,cooperativeStops:2,cleanAudits:2,sourceVerified:true,referenceEqual:true,persistence:true,uncertaintyRecovered:true,machineStopped:true),.init(boots:2,cooperativeStops:1,cleanAudits:2,sourceVerified:true,referenceEqual:true,persistence:true,uncertaintyRecovered:true,machineStopped:true),.init(boots:2,cooperativeStops:2,cleanAudits:1,sourceVerified:true,referenceEqual:true,persistence:true,uncertaintyRecovered:true,machineStopped:true),.init(boots:2,cooperativeStops:2,cleanAudits:2,sourceVerified:false,referenceEqual:true,persistence:true,uncertaintyRecovered:true,machineStopped:true),.init(boots:2,cooperativeStops:2,cleanAudits:2,sourceVerified:true,referenceEqual:false,persistence:true,uncertaintyRecovered:true,machineStopped:true),.init(boots:2,cooperativeStops:2,cleanAudits:2,sourceVerified:true,referenceEqual:true,persistence:false,uncertaintyRecovered:true,machineStopped:true),.init(boots:2,cooperativeStops:2,cleanAudits:2,sourceVerified:true,referenceEqual:true,persistence:true,uncertaintyRecovered:false,machineStopped:true),.init(boots:2,cooperativeStops:2,cleanAudits:2,sourceVerified:true,referenceEqual:true,persistence:true,uncertaintyRecovered:true,machineStopped:false)]
        for value in values { XCTAssertThrowsError(try value.validate()) }
    }
}
