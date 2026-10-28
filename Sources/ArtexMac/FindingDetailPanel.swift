import ArtexCore
import SwiftUI

@MainActor struct FindingDetailPanel: View {
    let model: FindingScreenModel
    let onTask: (String) -> Void
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in:[locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key,language:language) }
    var body: some View {
        let owner = model.store.viewOwner, revision = model.detailRevision
        ScrollView {
            VStack(alignment:.leading,spacing:14) {
                HStack {
                    Text(s(.findingUIDetails)).font(.title2.bold()); Spacer()
                    Button(s(.findingUIClose),systemImage:"xmark") { Task { await model.closeDetail(owner:owner,revision:revision) } }.disabled(!model.controlsAvailable)
                }
                FindingReadNotice(state:model.store.detail)
                if let row = model.store.detail.value {
                    Text(row.name).font(.headline).textSelection(.enabled)
                    Text(row.vulnclass).textSelection(.enabled)
                    HStack { Text(DashboardLabels.text(row.severity,domain:.severity,language:language)); Text(FindingPresentation.status(row.status,language:language)) }
                    if row.inherited {
                        Text(AppStrings.formatted(.findingUIInherited,language:language,values:["id":row.sourceTaskId ?? "—"])).foregroundStyle(.secondary)
                    } else if !row.canMutate { Text(s(.findingUILegacy)).foregroundStyle(.secondary) }
                    if let id = row.taskId {
                        Button(AppStrings.formatted(.findingUIOpenTask,language:language,values:["id":id])) { if model.store.viewOwner == owner, model.controlsAvailable { onTask(id) } }.disabled(!model.controlsAvailable)
                    }
                    if row.canMutate {
                        HStack {
                            Button(s(.findingUIEdit)) { if model.store.viewOwner == owner { _ = model.beginEdit(row) } }
                            Button(s(.findingUIDelete),role:.destructive) { if model.store.viewOwner == owner { _ = model.beginDelete(row) } }
                        }.disabled(!model.controlsAvailable || model.hasUnknownWrites)
                    }
                    section(.findingUISummary,row.summary); section(.findingUIAssets,row.assets.map(\.label).joined(separator:"\n"))
                    section(.findingUIEvidence,row.evidence)
                    if row.findingId != nil {
                        Button(s(.evidenceUITitle),systemImage:"network") { _ = model.beginTraffic(owner:owner,revision:revision) }
                            .disabled(!model.controlsAvailable || model.store.detail.isStale || model.store.detail.isLoading)
                    }
                    if row.reportStale { Text(s(.findingUIReportStale)).foregroundStyle(.orange) }
                    section(.findingUIReport,row.report)
                } else if !model.store.detail.isLoading { Text(s(.findingUINoSelection)).foregroundStyle(.secondary) }
            }.frame(maxWidth:.infinity,alignment:.leading).padding()
        }
    }
    private func section(_ key: AppStringKey,_ value: String) -> some View {
        VStack(alignment:.leading,spacing:6) { Text(s(key)).font(.headline); Text(value.isEmpty ? "—" : value).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }
    }
}

@MainActor struct FindingMutationNotice: View {
    let model: FindingScreenModel
    @Environment(\.locale) private var locale
    var body: some View {
        let language = AppLanguage.preferred(in:[locale.identifier])
        VStack(alignment:.leading,spacing:6) {
            if let error = model.store.mutationFailure { Text(error.text(language:language)).foregroundStyle(.red) }
            ForEach(model.trafficUnknownIDs,id:\.self) { id in
                HStack {
                    Text(AppStrings.formatted(.evidenceUIUnknownID,language:language,values:["id":id])).foregroundStyle(.orange)
                    Button(AppStrings.text(.evidenceUIReviewUnknown,language:language)) { _ = model.beginTrafficRecovery(id:id) }.disabled(!model.controlsAvailable)
                }
            }
            ForEach(model.store.unknownIDs.sorted(),id:\.self) { id in
                HStack {
                    Text(AppStrings.formatted(.findingUIUnknown,language:language,values:["id":id])).foregroundStyle(.orange)
                    Button(AppStrings.text(.findingUIAcknowledge,language:language)) { _ = model.beginAcknowledgement(id) }.disabled(!model.controlsAvailable)
                }
            }
        }
    }
}
