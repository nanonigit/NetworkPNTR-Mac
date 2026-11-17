import XCTest
import Observation
@testable import NetworkPNTRCore

@MainActor final class TaskHandoffTests: XCTestCase {
    private enum Command: CaseIterable {case create,update,control,batch,delete}
    private enum External: CaseIterable {case category,archive,bulk}
    private func label<T>(_ outcome: TaskMutationOutcome<T>) -> String {
        switch outcome {case .notStarted:"notStarted";case .rejected:"rejected";case .unconfirmed:"unconfirmed";case .discarded:"discarded";case .confirmed:"confirmed"}
    }
    private func perform(_ command: Command,_ store: TaskStore) async -> String {
        switch command {
        case .create:
            var draft=TaskCreateDraft();draft.description="synthetic";draft.goal="No agent execution in this test"
            return label(await store.create(draft))
        case .update:return label(await store.update(id:"7",patch:.init(pinned:true)))
        case .control:return label(await store.control(id:"7",action:.resume))
        case .batch:return label(await store.controlBatch(ids:["7","8"],action:.resume))
        case .delete:return label(await store.delete(id:"7"))
        }
    }
    private func acquire(_ kind: External,_ store: TaskStore) -> UUID? {
        switch kind {case .category:store.beginCategoryMutation();case .archive:store.beginArchiveMutation();case .bulk:store.beginBulkMutation()}
    }
    func testEveryDirectCommandCancelsAtBusyWithoutDispatchOrUncertainty() async throws {
        for command in Command.allCases {
            let api=ChatTestTransport(),store=TaskStore(service:.init(client:api))
            try api.enqueue(["error":"synthetic"],status:500)
            let work=Task {
                withObservationTracking {_ = store.isMutating} onChange:{withUnsafeCurrentTask{$0?.cancel()}}
                return await perform(command,store)
            }
            let result=await work.value
            XCTAssertEqual(result,"notStarted");XCTAssertTrue(api.calls.isEmpty);XCTAssertFalse(store.mutationUncertain);XCTAssertFalse(store.isMutating)
        }
    }
    func testEveryDirectCommandStopsAtBusyWithoutDispatchOrUncertainty() async throws {
        for command in Command.allCases {
            let api=ChatTestTransport(),store=TaskStore(service:.init(client:api))
            try api.enqueue(["error":"synthetic"],status:500)
            withObservationTracking {_ = store.isMutating} onChange:{MainActor.assumeIsolated{store.stop()}}
            let result=await perform(command,store)
            XCTAssertEqual(result,"notStarted");XCTAssertTrue(api.calls.isEmpty);XCTAssertFalse(store.mutationUncertain);XCTAssertFalse(store.isMutating)
        }
    }
    func testAllExternalLeaseKindsRejectSynchronousCancellation() async {
        for kind in External.allCases {
            let api=ChatTestTransport(),store=TaskStore(service:.init(client:api))
            let work=Task {
                withObservationTracking {_ = store.isMutating} onChange:{withUnsafeCurrentTask{$0?.cancel()}}
                return acquire(kind,store)
            }
            let token=await work.value
            XCTAssertNil(token);XCTAssertFalse(store.isMutating);XCTAssertTrue(api.calls.isEmpty)
        }
    }
    func testAllExternalLeaseKindsRejectSynchronousStop() {
        for kind in External.allCases {
            let api=ChatTestTransport(),store=TaskStore(service:.init(client:api))
            withObservationTracking {_ = store.isMutating} onChange:{MainActor.assumeIsolated{store.stop()}}
            XCTAssertNil(acquire(kind,store));XCTAssertFalse(store.isMutating);XCTAssertTrue(api.calls.isEmpty)
        }
    }
}
