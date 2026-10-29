import ArtexCore
import SwiftUI

@MainActor enum TrafficBindings {
    static func text(_ model: TrafficScreenModel, field: TrafficTextField, lease: UUID) -> Binding<String> {
        .init(get: { model.text(field, lease: lease) }, set: { _ = model.edit(field, text: $0, lease: lease) })
    }
    static func method(_ model: TrafficScreenModel, lease: UUID, owner: UUID) -> Binding<String> {
        .init(get: { model.store.query.method?.rawValue ?? "all" }, set: { value in
            guard model.store.owner == owner, value == "all" || CapturedHTTPMethod(rawValue: value) != nil else { return }
            _ = model.control(.method(CapturedHTTPMethod(rawValue: value)), lease: lease)
        })
    }
    static func status(_ model: TrafficScreenModel, lease: UUID, owner: UUID) -> Binding<String> {
        .init(get: { TrafficPresentation.status(model.store.query.status) }, set: { value in
            guard model.store.owner == owner else { return }
            let status: TrafficStatusFilter?
            switch value {
            case "all": status = nil
            case "2xx": status = .success
            case "3xx": status = .redirect
            case "4xx": status = .clientError
            case "5xx": status = .serverError
            default: return
            }
            _ = model.control(.status(status), lease: lease)
        })
    }
    static func size(_ model: TrafficScreenModel, lease: UUID, owner: UUID) -> Binding<Int> {
        .init(get: { model.store.query.size }, set: {
            guard model.store.owner == owner else { return }; _ = model.control(.size($0), lease: lease)
        })
    }
    static func host(_ model: TrafficScreenModel, host: String, lease: UUID, owner: UUID) -> Binding<Bool> {
        .init(get: { model.presentation == lease && model.store.owner == owner && model.store.selectedHosts.contains { Data($0.utf8) == Data(host.utf8) } }, set: {
            _ = model.toggleHost(host, selected: $0, lease: lease, owner: owner)
        })
    }
    static func preview(_ model: TrafficScreenModel, lease: UUID, owner: UUID, revision: UUID, id: String) -> Binding<Bool> {
        .init(get: { model.presentation == lease && model.previewRevision == revision && model.store.selectedExchange?.identity == Data(id.utf8) }, set: {
            if !$0 { model.closeDetail(id, lease: lease, owner: owner, revision: revision) }
        })
    }
    static func confirmation(_ model: TrafficScreenModel, lease: UUID, id: UUID?, owner: UUID) -> Binding<TrafficConfirmation?> {
        .init(get: { model.presentation == lease && model.deletionDialog?.id == id ? model.deletionDialog : nil }, set: {
            if $0 == nil, let id { _ = model.cancelDeletion(id: id, lease: lease, owner: owner) }
        })
    }
}
