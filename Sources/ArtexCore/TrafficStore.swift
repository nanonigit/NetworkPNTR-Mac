import Foundation
import Observation

public enum TrafficIntent:Sendable {case matchingHost,selectedHosts,purgeAll,capture(Bool)}
public struct TrafficConfirmation:Identifiable,Sendable {
    public let id:UUID,owner:UUID
    public var change:TrafficMutation {request.change}
    let session:UUID,activity:UUID,request:TrafficWriteRequest
}
public enum TrafficMutationOutcome:Sendable {
    case notStarted,unconfirmed,discarded,confirmed(TrafficMutationReceipt)
}

/// Window-owned traffic reads and frozen confirmations; uncertainty never clears implicitly.
@MainActor @Observable public final class TrafficStore {
    public let catalog=FindingReadState<CapturedTrafficPage>()
    public let hosts=FindingReadState<TrafficHosts>()
    public let settings=FindingReadState<TrafficCaptureSettings>()
    public let detail=FindingReadState<CapturedTrafficDetail>()
    public private(set) var query=TrafficQuery()
    public private(set) var owner=UUID()
    public private(set) var isActive=true
    public private(set) var flowRevision=UUID()
    public private(set) var hostRevision=UUID()
    public private(set) var selectedFlowIDs:[String]=[]
    public private(set) var selectedHosts:[String]=[]
    public private(set) var selectedExchange:CapturedTrafficExchange?
    public private(set) var confirmation:TrafficConfirmation?
    public private(set) var hasUnknownOutcome=false
    public private(set) var unknownRevision=UUID()
    public private(set) var unknownChange:TrafficMutation?
    public private(set) var lastReceipt:TrafficMutationReceipt?
    public private(set) var failure:AppErrorMessage?
    public var isMutating:Bool {write != nil}
    public var isRefreshing:Bool {readTicket != nil}
    public var canAutoRefresh:Bool {canRead && !isRefreshing && query.page==0}
    public var hasPrevious:Bool {editable && freshCatalog && query.page>0}
    public var hasNext:Bool {
        guard editable,freshCatalog,let total=catalog.value?.total,total>0 else {return false}
        return query.page<(total-1)/Int64(query.size)
    }
    public var canAcknowledgeUnknown:Bool {
        editable && hasUnknownOutcome && !isRefreshing && recoveredRevision==unknownRevision && recoveredOwner==owner
        && !catalog.isStale && !hosts.isStale && !settings.isStale
        && !catalog.isLoading && !hosts.isLoading && !settings.isLoading
    }
    @ObservationIgnored private let service:TrafficService
    @ObservationIgnored private var session=UUID()
    @ObservationIgnored private var activity=UUID()
    @ObservationIgnored private var transitioning=false
    @ObservationIgnored private var queuedStop=false
    @ObservationIgnored private var queuedReset=false
    @ObservationIgnored private var lifecycle=Lifecycle.none
    @ObservationIgnored private var unknownOperation:UUID?
    private var recoveredRevision:UUID?
    private var recoveredOwner:UUID?
    private var readTicket:UUID?
    private var write:Write?
    private enum Lifecycle {case none,stopping,resetting}
    private final class Write {
        let confirmation:TrafficConfirmation
        var handedOff=false,revoked=false
        init(_ confirmation:TrafficConfirmation) {self.confirmation=confirmation}
    }
    public init(service:TrafficService) {self.service=service}
    private var canRead:Bool {isActive && !transitioning && lifecycle == .none && write==nil && confirmation==nil && !Task.isCancelled}
    private var editable:Bool {canRead}
    private var freshCatalog:Bool {catalog.value?.isUnavailable==false && !catalog.isStale && !catalog.isLoading}
    private func current(_ expected:UUID) -> Bool {canRead && owner==expected}
    private func owns(_ ticket:Write) -> Bool {
        isActive && !transitioning && lifecycle == .none && !queuedStop && !queuedReset && !ticket.revoked
        && write === ticket && owner==ticket.confirmation.owner && session==ticket.confirmation.session && activity==ticket.confirmation.activity
    }
    private func update(_ body:()->Void) {
        precondition(!transitioning)
        transitioning=true;body();transitioning=false;drain()
    }
    private func drain() {
        guard !transitioning,lifecycle == .none else {return}
        if queuedReset {queuedReset=false;queuedStop=false;resetSession()}
        else if queuedStop {queuedStop=false;stop()}
    }
    private func invalidate(clear:Bool=false) {
        readTicket=nil;recoveredRevision=nil;recoveredOwner=nil
        catalog.invalidate(clear:clear);hosts.invalidate(clear:clear);settings.invalidate(clear:clear);detail.invalidate(clear:clear)
    }
    @discardableResult public func configure(_ value:TrafficQuery,owner expected:UUID) -> Bool {
        guard current(expected) else {return false}
        let path:Data,previous:Data
        do {path=Data(try value.pathString().utf8);previous=Data(try query.pathString().utf8)}
        catch {update{failure=AppErrorMessage(error)};return false}
        if path==previous {return true}
        update{query=value;owner=UUID();invalidate();failure=nil}
        return isActive
    }
    @discardableResult public func toggleFlow(id:String,selected:Bool,owner expected:UUID) -> Bool {
        guard current(expected),freshCatalog,catalog.value?.exchanges.contains(where:{$0.identity==Data(id.utf8)})==true else {return false}
        let values=selection(selectedFlowIDs,value:id,selected:selected)
        if sameSelection(selectedFlowIDs,values) {return true}
        update{selectedFlowIDs=values;flowRevision=UUID()};return isActive && owner==expected
    }
    @discardableResult public func toggleHost(_ host:String,selected:Bool,owner expected:UUID) -> Bool {
        guard current(expected),!hosts.isStale,!hosts.isLoading,hosts.value?.hosts.contains(where:{$0.identity==Data(host.utf8)})==true else {return false}
        let values=selection(selectedHosts,value:host,selected:selected)
        if sameSelection(selectedHosts,values) {return true}
        update{selectedHosts=values;hostRevision=UUID()};return isActive && owner==expected
    }
    private func selection(_ values:[String],value:String,selected:Bool) -> [String] {
        let exists=values.contains{Data($0.utf8)==Data(value.utf8)}
        if selected {return exists ? values:values+[value]}
        return values.filter{Data($0.utf8) != Data(value.utf8)}
    }
    private func sameSelection(_ left:[String],_ right:[String])->Bool {left.map{Data($0.utf8)}==right.map{Data($0.utf8)}}
    private func batchSelection(_ existing:[String],visible:[String],selected:Bool)->[String] {
        let visibleIDs=Set(visible.map{Data($0.utf8)})
        if !selected {return existing.filter{!visibleIDs.contains(Data($0.utf8))}}
        var known=Set(existing.map{Data($0.utf8)}),result=existing
        for value in visible where known.insert(Data(value.utf8)).inserted {result.append(value)}
        return result
    }
    @discardableResult public func selectVisibleFlows(_ selected:Bool,owner expected:UUID)->Bool {
        guard current(expected),freshCatalog,let rows=catalog.value?.exchanges else {return false}
        let values=batchSelection(selectedFlowIDs,visible:rows.map(\.id),selected:selected)
        if sameSelection(selectedFlowIDs,values) {return true}
        update{selectedFlowIDs=values;flowRevision=UUID()};return isActive && owner==expected
    }
    @discardableResult public func selectAllHosts(_ selected:Bool,owner expected:UUID)->Bool {
        guard current(expected),!hosts.isStale,!hosts.isLoading,let rows=hosts.value?.hosts else {return false}
        let values=batchSelection(selectedHosts,visible:rows.map(\.host),selected:selected)
        if sameSelection(selectedHosts,values) {return true}
        update{selectedHosts=values;hostRevision=UUID()};return isActive && owner==expected
    }
    @discardableResult public func clearFlowSelection(owner expected:UUID) -> Bool {
        guard current(expected) else {return false};if selectedFlowIDs.isEmpty {return true};update{selectedFlowIDs=[];flowRevision=UUID()};return isActive && owner==expected
    }
    @discardableResult public func clearHostSelection(owner expected:UUID) -> Bool {
        guard current(expected) else {return false};if selectedHosts.isEmpty {return true};update{selectedHosts=[];hostRevision=UUID()};return isActive && owner==expected
    }
    @discardableResult public func selectExchange(id:String?,owner expected:UUID) -> Bool {
        guard current(expected) else {return false}
        let row:CapturedTrafficExchange?
        if let id {
            guard freshCatalog,let found=catalog.value?.exchanges.first(where:{$0.identity==Data(id.utf8)}) else {return false};row=found
        } else {row=nil}
        if selectedExchange?.identity==row?.identity {return true}
        update{selectedExchange=row;detail.invalidate(clear:true)};return isActive && owner==expected
    }
    public func refresh() async {
        guard canRead,readTicket==nil else {return}
        let token=UUID(),expected=owner,epoch=session,period=activity,revision=unknownRevision,capturedQuery=query
        update{readTicket=token;recoveredRevision=nil;recoveredOwner=nil}
        defer {if readTicket==token {update{readTicket=nil}}}
        func valid()->Bool {current(expected) && readTicket==token && session==epoch && activity==period}
        guard valid() else {return}
        let pageOK=await catalog.refresh{[service] in try await service.list(capturedQuery)}
        guard valid() else {return}
        let hostsOK=await hosts.refresh{[service] in try await service.hosts()}
        guard valid() else {return}
        let settingsOK=await settings.refresh{[service] in try await service.captureSettings()}
        guard valid() else {return}
        if pageOK && hostsOK && settingsOK && hasUnknownOutcome && unknownRevision==revision {
            update{recoveredRevision=revision;recoveredOwner=expected}
        }
    }
    public func refreshDetail() async {
        guard canRead,let selectedExchange else {return}
        let expected=owner,id=selectedExchange.id,epoch=session,period=activity
        _ = await detail.refresh{[service,weak self] in
            guard let self,self.current(expected),self.session==epoch,self.activity==period,self.selectedExchange?.identity==Data(id.utf8) else {throw CancellationError()}
            return try await service.detail(id:id)
        }
    }
    @discardableResult public func prepare(_ intent:TrafficIntent,owner expected:UUID) -> Bool {
        guard current(expected),!isRefreshing,!hasUnknownOutcome else {return false}
        let change:TrafficMutation
        switch intent {
        case .matchingHost:guard freshCatalog else {return false};change = .deleteMatchingHost(query.host)
        case .selectedHosts:guard freshCatalog,!hosts.isStale,!hosts.isLoading else {return false};change = .deleteHosts(selectedHosts)
        case .purgeAll:guard freshCatalog else {return false};change = .purgeAll
        case .capture(let value):guard settings.value != nil,!settings.isStale,!settings.isLoading else {return false};change = .capture(value)
        }
        let prepared:TrafficWriteRequest
        do {prepared=try service.prepare(change)}catch {update{failure=AppErrorMessage(error)};return false}
        let value=TrafficConfirmation(id:UUID(),owner:expected,session:session,activity:activity,request:prepared)
        update{confirmation=value;failure=nil}
        return isActive && owner==expected && confirmation?.id==value.id
    }
    @discardableResult public func cancelConfirmation(id:UUID,owner expected:UUID) -> Bool {
        guard isActive,!transitioning,write==nil,owner==expected,confirmation?.id==id else {return false}
        update{confirmation=nil};return true
    }
    public func confirm(id:UUID,owner expected:UUID) async -> TrafficMutationOutcome {await confirm(id:id,owner:expected,onDispatch:{})}
    func confirm(id:UUID,owner expected:UUID,onDispatch:@MainActor () throws -> Void) async -> TrafficMutationOutcome {
        guard isActive,!transitioning,lifecycle == .none,!Task.isCancelled,write==nil,!hasUnknownOutcome,
              owner==expected,let value=confirmation,value.id==id,value.owner==expected,value.session==session,value.activity==activity else {return .notStarted}
        let ticket=Write(value)
        update{write=ticket;confirmation=nil;failure=nil;lastReceipt=nil;invalidate()}
        defer {if write === ticket {update{write=nil}}}
        guard owns(ticket),!Task.isCancelled else {return .notStarted}
        do {
            let receipt=try await service.execute(value.request){
                try onDispatch()
                guard self.owns(ticket),!Task.isCancelled else {throw CancellationError()}
                ticket.handedOff=true
            }
            guard value.session==session else {return .discarded}
            guard owns(ticket),!Task.isCancelled else {update{markUnknown(ticket)};return .discarded}
            update{
                lastReceipt=receipt
                if case .capture(let setting)=receipt {settings.acceptConfirmed(setting)}
                else {
                    query.page=0;selectedExchange=nil;detail.invalidate(clear:true)
                    switch value.change {case .deleteHosts,.purgeAll:selectedHosts=[];hostRevision=UUID();default:break}
                }
            }
            guard owns(ticket) else {return .discarded}
            return .confirmed(receipt)
        } catch {
            guard value.session==session else {return .discarded}
            guard ticket.handedOff else {return .notStarted}
            update{markUnknown(ticket)}
            guard owns(ticket) else {return .discarded}
            if !(error is CancellationError) {update{failure=AppErrorMessage(error)}}
            return .unconfirmed
        }
    }
    private func markUnknown(_ ticket:Write) {
        if unknownOperation != ticket.confirmation.id {unknownOperation=ticket.confirmation.id;unknownRevision=UUID()}
        hasUnknownOutcome=true;recoveredRevision=nil;recoveredOwner=nil
        if session==ticket.confirmation.session {unknownChange=ticket.confirmation.change}
    }
    @discardableResult public func acknowledgeUnknown(owner expected:UUID,revision:UUID) -> Bool {
        guard current(expected),canAcknowledgeUnknown,revision==unknownRevision else {return false}
        update{hasUnknownOutcome=false;unknownChange=nil;unknownOperation=nil;unknownRevision=UUID();recoveredRevision=nil;recoveredOwner=nil;failure=nil};return true
    }
    @discardableResult public func stop(ifOwnedBy expected:UUID?=nil)->Bool {
        guard expected==nil || expected==owner,lifecycle != .resetting else {return false}
        if transitioning || lifecycle == .stopping {
            if lifecycle == .none {queuedStop=true;write?.revoked=true};return true
        }
        guard isActive else {return false};deactivate(reset:false);return true
    }
    public func resetSession() {
        guard lifecycle != .resetting else {return}
        if transitioning || lifecycle == .stopping {queuedReset=true;queuedStop=false;write?.revoked=true;return}
        deactivate(reset:true)
    }
    private func deactivate(reset:Bool) {
        lifecycle=reset ? .resetting:.stopping
        update{
            if reset {session=UUID();unknownChange=nil}
            if let write,write.handedOff {markUnknown(write)}
            write?.revoked=true;activity=UUID();isActive=false;confirmation=nil;invalidate(clear:true)
            selectedFlowIDs=[];selectedHosts=[];flowRevision=UUID();hostRevision=UUID();selectedExchange=nil;lastReceipt=nil;failure=nil;owner=UUID()
        }
        lifecycle = .none;drain()
    }
    public func resume() {
        guard !isActive,!transitioning,lifecycle == .none else {return}
        update{activity=UUID();owner=UUID();isActive=true;invalidate(clear:true)}
    }
}
