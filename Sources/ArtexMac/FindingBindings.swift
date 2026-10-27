import ArtexCore
import SwiftUI

@MainActor enum FindingBindings {
    static func detail(_ model: FindingScreenModel,owner: UUID,revision: UUID) -> Binding<Bool> {
        Binding(get:{model.store.selectedDetail != nil},set:{if !$0 { Task { await model.closeDetail(owner:owner,revision:revision) } }})
    }
    static func draft(_ model: FindingScreenModel,id: UUID,key: ReferenceWritableKeyPath<FindingScreenModel,String>) -> Binding<String> {
        Binding(get:{model[keyPath:key]},set:{if model.dialog?.id == id, !model.busy, !model.dialogUncertain { model[keyPath:key] = $0 }})
    }
    static func selected(_ model: FindingScreenModel,id: String,owner: UUID) -> Binding<Bool> {
        Binding(get:{model.store.viewOwner == owner && model.store.selectedIDs.contains(id)},set:{
            guard model.controlsAvailable else { return }; model.store.setSelected(id,selected:$0,owner:owner)
        })
    }
    static func dialog(_ model: FindingScreenModel,id: UUID?) -> Binding<FindingDialog?> {
        Binding(get:{model.dialog},set:{if $0 == nil, let id { model.close(dialogID:id) }})
    }
    static func filter(_ model: FindingScreenModel,owner: UUID,get: @escaping (FindingQuery) -> String,set: @escaping (inout FindingQuery,String) -> Void) -> Binding<String> {
        Binding(get:{get(model.store.filters)},set:{value in
            guard model.store.viewOwner == owner, model.controlsAvailable else { return }
            var query = model.store.filters; query.search = model.searchDraft; set(&query,value); _ = model.configureFilters(query)
        })
    }
}
