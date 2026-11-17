import NetworkPNTRCore
import Foundation
import Observation

/// A window retains uncertainty across navigation, but never shares it with another authentication owner.
@MainActor @Observable final class LLMWorkspace {
    private(set) var store: LLMStore?
    @ObservationIgnored private var owner: AnyObject?
    func belongs(to owner: AnyObject) -> Bool {
        // Track first attachment even when the private owner has not been set.
        store != nil && self.owner === owner
    }
    func attach(owner: AnyObject, make: () -> LLMStore) {
        guard !belongs(to: owner) else { return }
        store?.stop()
        self.owner = owner
        store = make()
    }
    func reset() {
        let old = store
        owner = nil; store = nil
        old?.stop()
    }
}
