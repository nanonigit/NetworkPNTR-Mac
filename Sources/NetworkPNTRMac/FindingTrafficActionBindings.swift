import SwiftUI
import Foundation
import NetworkPNTRCore

@MainActor enum FindingTrafficActionBindings {
    static func dialog(_ actions: FindingTrafficActions,id: UUID?) -> Binding<FindingTrafficActionDialog?> {
        Binding(get:{actions.dialog?.id == id ? actions.dialog : nil},set:{ value in if value == nil, let id { actions.close(id:id) } })
    }
    static func note(_ actions: FindingTrafficActions,id: UUID) -> Binding<String> {
        Binding(get:{actions.dialog?.id == id ? actions.noteDraft : ""},set:{ value in
            if actions.dialog?.id == id, !actions.isSubmitting, !actions.uncertain { actions.noteDraft = value }
        })
    }
    static func role(_ actions: FindingTrafficActions,id: UUID) -> Binding<String> {
        Binding(get:{actions.dialog?.id == id ? actions.roleDraft?.rawValue ?? "" : ""},set:{ value in
            if actions.dialog?.id == id, !actions.isSubmitting, !actions.uncertain { actions.roleDraft = FindingTrafficRole(rawValue:value) }
        })
    }
}
