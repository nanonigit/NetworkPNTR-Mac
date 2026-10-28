import ArtexCore
import Darwin
import Foundation

@MainActor enum CapturedProbe {
    static func run(_ args: [String]) async {
        #if DEBUG
        guard args.count==3 else {usage();exit(2)}
        await runDebug(args)
        #else
        usage();exit(2)
        #endif
    }
    private static func usage() { FileHandle.standardError.write(Data("Usage: DEBUG VMProbe --captured ARTIFACTS NEW_PRIVATE_OUTPUT REFERENCE_RECEIPT\n".utf8)) }
    #if DEBUG
    private final class Vault: SessionVault {
        var token: String?
        func load() throws -> String? {token}
        func save(_ token: String) throws {self.token=token}
        func remove() throws {token=nil}
    }
    /// One owned diagnostic response is withheld after the actual backend write completes.
    final class WithheldResponse: BackendJSONTransport {
        let base: any BackendJSONTransport
        var path: String?
        private(set) var withheld = false
        private(set) var edits = 0
        init(_ base: any BackendJSONTransport) {self.base=base}
        func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
            if method=="PATCH" {edits+=1}
            let value=try await base.send(method:method,path:path,body:body,bearer:bearer)
            if method=="PATCH",path==self.path,value.status==200 {
                self.path=nil;withheld=true
                throw RuntimeError.integrity("diagnostic withheld response")
            }
            return value
        }
    }
    private static func canonical(_ value: Any) throws -> Data {try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys])}
    private static func write(_ value: [String:Any],_ url: URL) throws {try canonical(value).write(to:url,options:.atomic)}
    private static func progress(_ value: String) {print("captured_stage="+value);fflush(stdout)}
    private static func require(_ value: Bool) throws {try CapturedProbeContract.require(value)}
    private static func same(_ left: Any,_ right: Any) throws -> Bool {try canonical(left)==canonical(right)}
    private static func confirmed(_ value: FindingTrafficMutationOutcome) throws -> FindingTraffic {
        guard case .confirmed(let result)=value else {throw RuntimeError.integrity("captured write receipt")};return result
    }
    private static func fingerprint(_ value: CapturedTrafficExchange) -> [String:Any] {
        ["id":value.id,"ts":value.ts,"host":value.host,"method":value.method,"url":value.url,"content_type":value.contentType,"status":value.status,"resp_len":value.responseLength]
    }
    private static func records(_ service: CapturedTrafficService) async throws -> [CapturedTrafficExchange] {
        var query=CapturedTrafficQuery();query.size=500
        let page=try await service.list(query)
        try require(!page.isUnavailable && page.count==29 && page.total==29 && page.exchanges.count==29)
        var indices=Set<Int>()
        for row in page.exchanges {
            let index=try CapturedProbeContract.ordinal(row.url);try require(indices.insert(index).inserted)
            let expected=try CapturedProbeContract.bytes(index,side:.response)
            try require(row.host=="127.0.0.1" && row.status==200 && row.method==(index%2==0 ? "GET":"POST") && row.responseLength==expected.count && row.contentType==([2,4].contains(index) ? "application/octet-stream":"text/plain; charset=utf-8"))
        }
        try require(indices==Set(0..<29))
        return try page.exchanges.sorted{try CapturedProbeContract.ordinal($0.url)<CapturedProbeContract.ordinal($1.url)}
    }
    private static func exercise(_ api: WithheldResponse,_ session: AuthenticationSession,_ traffic: CapturedTrafficService,_ rows: [CapturedTrafficExchange],_ directory: URL) async throws -> ([String:Any],FindingTraffic,Bool) {
        progress("exercise-pages")
        let byID=Dictionary(uniqueKeysWithValues:rows.map{($0.id,$0)})
        var paged=[CapturedTrafficExchange]()
        for index in 0...1 {
            var query=CapturedTrafficQuery();query.page=Int64(index)
            let page=try await traffic.list(query);try require(page.count==29 && page.total==29 && page.exchanges.count==(index==0 ? 25:4))
            for row in page.exchanges {guard let expected=byID[row.id] else {throw RuntimeError.integrity("captured page ID")};try require(try same(fingerprint(row),fingerprint(expected)))}
            paged+=page.exchanges
        }
        try require(Set(paged.map(\.identity))==Set(rows.map(\.identity)) && paged.count==29)
        var filters=[[String:Any]]()
        for index in 0..<6 {
            var query=CapturedTrafficQuery();query.size=500;let expected:[CapturedTrafficExchange];let label:String
            switch index {
            case 0:query.host="127.0.0.1";expected=rows;label="host=127.0.0.1"
            case 1:query.host="192.0.2.1";expected=[];label="host=192.0.2.1"
            case 2:query.method = .get;expected=rows.enumerated().filter{$0.offset%2==0}.map(\.element);label="method=GET"
            case 3:query.method = .post;expected=rows.enumerated().filter{$0.offset%2==1}.map(\.element);label="method=POST"
            case 4:query.keyword="ordinal 05";expected=[rows[5]];label="q=ordinal+05"
            default:query.keyword="日本語";expected=rows.enumerated().filter{$0.offset%2==1}.map(\.element);label="q=%E6%97%A5%E6%9C%AC%E8%AA%9E"
            }
            let page=try await traffic.list(query);try require(page.count==29 && page.total==Int64(expected.count) && page.exchanges.count==expected.count && Set(page.exchanges.map(\.identity))==Set(expected.map(\.identity)))
            for row in page.exchanges {guard let original=byID[row.id] else {throw RuntimeError.integrity("captured filter ID")};try require(try same(fingerprint(row),fingerprint(original)))}
            filters.append(["query":label,"total":expected.count])
        }
        let raw=try await traffic.detail(id:rows[1].id)
        try require(Data(raw.response.utf8).range(of:CapturedProbeContract.literal) != nil)
        progress("exercise-picker")
        let findings=FindingService(client:api),service=FindingTrafficService(client:api)
        let target=try await findings.detail(id:"9101")
        let store=FindingTrafficStore(service:service);try require(store.select(target));await store.refreshSummary()
        try require(store.summary.value?.bindings.isEmpty==true && !store.summary.isStale)
        let picker=CapturedTrafficPickerStore(service:traffic,evidence:store);await picker.refreshCatalog()
        try require(picker.toggle(id:paged[0].id,selected:true,owner:picker.owner))
        try require(picker.nextPage(owner:picker.owner));await picker.refreshCatalog()
        try require(picker.toggle(id:paged[25].id,selected:true,owner:picker.owner));try require(picker.selectedCount==2)
        try require(picker.clearSelection(owner:picker.owner))
        for index in [3,4] {
            guard let position=paged.firstIndex(where:{$0.identity==rows[index].identity}) else {throw RuntimeError.integrity("captured picker page")}
            var query=CapturedTrafficQuery();query.page=Int64(position/25)
            try require(picker.configure(query,owner:picker.owner));await picker.refreshCatalog()
            try require(picker.toggle(id:rows[index].id,selected:true,owner:picker.owner))
        }
        guard let previewPage=paged.firstIndex(where:{$0.identity==rows[3].identity}) else {throw RuntimeError.integrity("captured picker preview page")}
        var previewQuery=CapturedTrafficQuery();previewQuery.page=Int64(previewPage/25)
        try require(picker.configure(previewQuery,owner:picker.owner));await picker.refreshCatalog()
        try require(picker.selectPreview(id:rows[3].id,owner:picker.owner));await picker.refreshPreview()
        try require(picker.preview.value != nil && !picker.preview.isStale)
        let bound=try confirmed(await picker.bind(owner:picker.owner));picker.stop()
        try require(bound.bindings.count==2 && zip(bound.bindings,[3,4]).allSatisfy{row,index in row.snapshot.sourceTrafficId==rows[index].id && row.snapshot.url==rows[index].url && row.role=="supporting" && row.note.isEmpty})
        progress("exercise-bodies")
        var bodies=[[String:Any]](),previews=[[String:Any]]()
        for binding in bound.bindings {
            let index=try CapturedProbeContract.ordinal(binding.snapshot.url)
            try require(store.selectBinding(binding.id,owner:store.owner));await store.refreshDetail()
            guard let detail=store.detail.value,!store.detail.isStale else {throw RuntimeError.integrity("captured store detail")}
            try require(detail.binding.snapshotId==binding.snapshotId)
            for side in [FindingEvidenceSide.request,.response] {
                let expected=try CapturedProbeContract.bytes(index,side:side)
                let download=try FindingEvidenceDownload(binding:binding,side:side)
                try require(download.expectedSize==expected.count && download.expectedSHA256==ArtifactIntegrity.sha256(expected))
                let destination=directory.appendingPathComponent(String(index)+"-"+side.rawValue+".bin")
                let receipt=try await session.authenticatedEvidenceExport(download,destination:EvidenceExportDestination(newFileURL:destination))
                let saved=try receipt.commit();try receipt.discard()
                try require(saved.stagingCleanupComplete && saved.directorySynced && (try Data(contentsOf:saved.url))==expected)
                bodies.append(["ordinal":index,"side":side.rawValue,"bytes":expected.count,"sha256":ArtifactIntegrity.sha256(expected),"full_byte_equal":true])
                var offset:Int64=0,joined=Data()
                while true {
                    try require(store.configureBody(side:side,offset:offset,owner:store.owner));await store.refreshBody()
                    guard let value=store.body.value,!store.body.isStale else {throw RuntimeError.integrity("captured store body")}
                    var proof=try CapturedProbeContract.validate(value,data:expected,offset:offset)
                    if offset==0 { _ = try CapturedProbeContract.validate(side == .request ? detail.request:detail.response,data:expected,offset:0) }
                    proof["ordinal"]=index;proof["side"]=side.rawValue;previews.append(proof);joined.append(Data(value.content.utf8))
                    if value.binary || !value.truncated {if !value.binary {try require(joined==expected)};break}
                    offset=value.nextOffset
                }
            }
        }
        let first=bound.bindings[0].id,second=bound.bindings[1].id
        progress("exercise-uncertainty")
        api.path="/api/exploration/findings/9101/traffic/"+first
        let uncertain=await store.apply(.edit(bindingID:first,role:.verification,note:CapturedProbeContract.note),owner:store.owner)
        guard case .unconfirmed=uncertain else {throw RuntimeError.integrity("captured uncertainty")}
        try require(api.withheld && api.edits==1 && store.unknownIDs==["9101"])
        let blocked=await store.apply(.remove(bindingID:first),owner:store.owner)
        guard case .notStarted=blocked else {throw RuntimeError.integrity("captured unknown write gate")}
        await store.refreshSummary();try require(store.unknownIDs==["9101"] && api.edits==1 && !store.summary.isStale)
        guard let edited=store.summary.value else {throw RuntimeError.integrity("captured edited readback")}
        let editedFirst=try CapturedProbeContract.editedBinding(edited,first:first,second:second)
        try require(editedFirst.role=="verification" && Data(editedFirst.note.utf8)==Data(CapturedProbeContract.note.utf8))
        try require(!store.acknowledgeUnknown("9101",owner:store.owner,revision:UUID()))
        try require(store.acknowledgeUnknown("9101",owner:store.owner,revision:store.unknownRevision) && store.unknownIDs.isEmpty)
        do {_ = try await service.apply(.edit(bindingID:first,role:.baseline,note:"must not apply"),to:target,snapshot:bound);throw RuntimeError.integrity("captured missing conflict")}
        catch BackendAPIError.status(409) { }
        let readback=try await service.list(findingID:"9101");try require(try same(CapturedProbeContract.normalized(edited),CapturedProbeContract.normalized(readback)))
        progress("exercise-order-remove")
        let ordered=try confirmed(await store.apply(.reorder([second,first]),owner:store.owner))
        try require(ordered.bindings.map(\.id)==[second,first] && ordered.bindings.map(\.position)==[0,1])
        let removed=try confirmed(await store.apply(.remove(bindingID:first),owner:store.owner))
        try require(removed.bindings.map(\.id)==[second])
        let metadata=try await findings.detail(id:"9101");try require(metadata.evidenceVersion==removed.version && metadata.trafficCount==1 && metadata.reportStale)
        var states=[String:Any]();for (key,value) in [("bound",bound),("edited",edited),("ordered",ordered),("removed",removed)] {states[key]=try CapturedProbeContract.normalized(value)}
        store.stop()
        return (["metadata":["evidence_version":metadata.evidenceVersion,"report_evidence_version":metadata.reportEvidenceVersion,"traffic_count":metadata.trafficCount,"report_stale":metadata.reportStale],"filters":filters,"bodies":bodies,"previews":previews,"states":states],removed,true)
    }
    private static func runDebug(_ args: [String]) async {
        let artifacts=URL(fileURLWithPath:args[0]),output=URL(fileURLWithPath:args[1]),reference=URL(fileURLWithPath:args[2])
        let controller=VMController(),vault=Vault()
        var report:[String:Any]=["passed":false,"nativeUIAcceptance":false,"fullGoalComplete":false]
        var stage="prepare",created=false,tokens=[String](),boots=0,stops=0,audits=0
        var sourceHashes=[String:String](),initialRows=[CapturedTrafficExchange](),finalState:FindingTraffic?
        var result=[String:Any](),recovery=false
        var executedSourceHashes=[String:String](),sourceAudits=0
        do {
            try require(mkdir(output.path,0o700)==0);created=true
            let resource=try reference.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
            try require(resource.isRegularFile==true && resource.isSymbolicLink != true && (resource.fileSize ?? Int.max)<=1024*1024)
            let referenceBytes=try Data(contentsOf:reference);try require(referenceBytes.count<=1024*1024)
            guard let receipt=try JSONSerialization.jsonObject(with:referenceBytes) as? [String:Any],receipt["passed"] as? Bool==true,let referenceValue=receipt["reference"] as? [String:Any],let expected=referenceValue["exercise"] as? [String:Any] else {throw RuntimeError.integrity("captured reference receipt")}
            let manifest=try GuestArtifacts.load(from:artifacts)
            guard let metadata=try JSONSerialization.jsonObject(with:Data(contentsOf:artifacts.appendingPathComponent("manifest.json"))) as? [String:Any] else {throw RuntimeError.integrity("captured artifact manifest")}
            try require(manifest.cpuCount==1 && metadata["captureListener"] as? String=="127.0.0.1:8788" && metadata["backendSHA256"] as? String=="0ebad83ddda276b03b415d64ce30af44e7a587860f3b660c12563462a0ac5e80")
            report["referenceSHA256"]=ArtifactIntegrity.sha256(referenceBytes);report["artifactManifest"]=metadata
            let disk=output.appendingPathComponent("state.ext4");_ = try PersistentGuestDisk.createIfMissing(at:disk,byteCount:2*1024*1024*1024)
            let password=UUID().uuidString+"-captured-fixture";tokens.append(password)
            for index in 1...2 {
                stage="boot-"+String(index);progress(stage);let provisioning=try GuestProvisioning.generate();tokens += [provisioning.setupToken,provisioning.transportToken]
                let logs=output.appendingPathComponent("boot-"+String(index))
                try await controller.start(artifacts:artifacts,logs:logs,readinessTimeout:.seconds(120),dataDisk:disk,provisioning:provisioning);boots+=1
                for _ in 0..<1600 {if controller.guestReady || controller.state == .failed {break};try await Task.sleep(for:.milliseconds(100))}
                try require(controller.guestReady && controller.configuredCPUCount==1)
                let raw=BackendJSONClient(runtime:controller,provisioning:provisioning),session=AuthenticationSession(client:BackendJSONClient(runtime:controller,provisioning:provisioning),vault:vault,setupToken:provisioning.setupToken)
                try require(try await raw.send(method:"GET",path:"/api/traffic",body:nil,bearer:nil).status==401)
                await session.refresh();if index==1 {await session.setup(password:password,confirmation:password)}
                try require(session.phase == .authenticated);if let token=vault.token {tokens.append(token)}
                let api=WithheldResponse(AuthenticatedBackendClient(session:session)),traffic=CapturedTrafficService(client:api),fixture=try CapturedFixtureClient(client:api)
                if index==1 {
                    sourceHashes=fixture.sourceSHA256;let empty=try await traffic.list();try require(!empty.isUnavailable && empty.count==0 && empty.total==0 && empty.exchanges.isEmpty)
                    stage="fixture";progress(stage);_ = try await fixture.prepare();initialRows=try await records(traffic)
                    let downloads=output.appendingPathComponent("downloads");try FileManager.default.createDirectory(at:downloads,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
                    stage="exercise";progress(stage);(result,finalState,recovery)=try await exercise(api,session,traffic,initialRows,downloads)
                    let audited=try await fixture.audit();result["counts"]=audited.counts;executedSourceHashes=audited.sourceSha256;sourceAudits+=1
                } else {
                    stage="persisted-audit";progress(stage);try require(fixture.sourceSHA256==sourceHashes);let audited=try await fixture.audit()
                    try require(try same(audited.counts,result["counts"] ?? [:]));try require(audited.sourceSha256==executedSourceHashes);sourceAudits+=1
                    let persisted=try await records(traffic);try require(try same(initialRows.map(fingerprint),persisted.map(fingerprint)))
                    guard let finalState else {throw RuntimeError.integrity("captured final state")}
                    let current=try await FindingTrafficService(client:api).list(findingID:"9101");try require(try same(CapturedProbeContract.normalized(finalState),CapturedProbeContract.normalized(current)))
                    let metadata=try await FindingService(client:api).detail(id:"9101");try require(metadata.trafficCount==1 && metadata.evidenceVersion==finalState.version && metadata.reportStale)
                    report["persistence"]=true
                }
                try await controller.stop();try require(controller.state == .stopped && !controller.hasMachine);stops+=1
                let audit=GuestBootDiagnostics.audit(logDirectory:logs,tokens:tokens)
                try require(audit.credentialsAbsent && audit.isolationWitnessesPresent && audit.diagnostics.isEmpty && audit.formatStageObserved==(index==1));audits+=1
            }
            try require(sourceAudits==2 && executedSourceHashes==sourceHashes)
            let equal=try same(result,expected)
            try CapturedProbeContract.Completion(boots:boots,cooperativeStops:stops,cleanAudits:audits,sourceVerified:sourceAudits==2 && executedSourceHashes==sourceHashes,referenceEqual:equal,persistence:report["persistence"] as? Bool==true,uncertaintyRecovered:recovery,machineStopped:!controller.hasMachine).validate()
            report.merge(["passed":true,"stage":"complete","boots":boots,"cooperativeStops":stops,"cleanAudits":audits,"sourceSHA256":sourceHashes,"exercise":result,"referenceEqual":equal,"uncertaintyRecovered":recovery,"machineStopped":true]){_,new in new}
            try write(report,output.appendingPathComponent("captured-native.json"));progress("complete")
        } catch {
            if controller.hasMachine {try? await controller.forceStop()}
            report["passed"]=false;report["stage"]=stage;report["errorType"]=String(reflecting:type(of:error));report["machineStopped"] = !controller.hasMachine
            if created {try? write(report,output.appendingPathComponent("captured-native.json"))}
            FileHandle.standardError.write(Data(("FAIL captured native stage="+stage+"\n").utf8));exit(1)
        }
    }
    #endif
}
