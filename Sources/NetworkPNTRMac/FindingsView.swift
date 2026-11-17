import NetworkPNTRCore
import SwiftUI

@MainActor struct FindingsView: View {
    let model: FindingScreenModel
    let onTask: (String) -> Void
    var body: some View {
        FindingsContent(model:model,onTask:onTask)
            .task { model.reads.activate() }
            .task { await model.store.runStats() }
            .onDisappear { model.stop() }
    }
}

@MainActor struct FindingsContent: View {
    let model: FindingScreenModel
    let onTask: (String) -> Void
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in:[locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key,language:language) }
    var body: some View {
        let owner = model.store.viewOwner, dialogID = model.dialog?.id, trafficID = model.trafficWorkspace?.id
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text(s(.findingUITitle)).font(.largeTitle.bold()); Spacer()
                if model.store.isRefreshingView || model.reads.isPending { ProgressView().controlSize(.small) }
                Button(s(.findingUIRefresh),systemImage:"arrow.clockwise") { model.reads.request(forceTree:true,stats:true) }
                    .keyboardShortcut("r",modifiers:.command).disabled(!model.controlsAvailable)
            }
            Picker(s(.findingUITitle),selection:Binding(get:{model.store.view.rawValue},set:{if model.store.viewOwner == owner, let view = FindingView(rawValue:$0) { _ = model.setView(view) }})) {
                ForEach(FindingView.allCases,id:\.rawValue) { Text(s(FindingPresentation.viewKey($0))).tag($0.rawValue) }
            }.pickerStyle(.segmented).disabled(!model.controlsAvailable)
            FindingStatsStrip(model:model)
            FindingFilterBar(model:model)
            if let error = model.store.configurationFailure { Text(error.text(language:language)).foregroundStyle(.red) }
            FindingMutationNotice(model:model)
            HStack {
                Text(AppStrings.formatted(.findingUISelected,language:language,values:["count":String(model.store.selectedIDs.count)])).font(.caption)
                Button(s(.findingUIClear)) { if model.store.viewOwner == owner, model.controlsAvailable { model.store.clearSelection() } }.disabled(!model.controlsAvailable || model.store.selectedIDs.isEmpty)
                Spacer()
                Button(s(.findingUISelectPage)) { if model.controlsAvailable { model.store.setAllVisible(selected:true,owner:owner) } }.disabled(!model.controlsAvailable)
            }
            if model.store.view == .asset {
                HSplitView {
                    FindingAssetPanel(model:model).frame(minWidth:190,idealWidth:230,maxWidth:320)
                    flat
                }
            } else if model.store.view == .grouped { FindingGroupsPanel(model:model,onTask:onTask) }
            else { flat }
            Text(s(.findingUIAdvancedPending)).font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).navigationTitle(s(.findingUITitle))
        .inspector(isPresented:FindingBindings.detail(model,owner:owner,revision:model.detailRevision)) {
            FindingDetailPanel(model:model,onTask:onTask).inspectorColumnWidth(min:280,ideal:360,max:520)
        }
        .sheet(item:FindingBindings.traffic(model,id:trafficID)) { workspace in
            FindingTrafficSheet(model:workspace) { model.closeTraffic(id:workspace.id) }
        }
        .sheet(item:FindingBindings.dialog(model,id:dialogID)) { context in FindingDialogView(model:model,contextID:context.id) }
    }
    private var flat: some View {
        VStack(alignment:.leading,spacing:8) {
            FindingReadNotice(state:model.store.flat.read)
            FindingTable(model:model,rows:model.store.flat.read.value?.items ?? [],loaded:model.store.flat.read.value != nil,loading:model.store.flat.read.isLoading,onTask:onTask)
            FindingPager(model:model,page:model.store.flat.page,size:model.store.flat.size,total:model.store.flat.read.value?.total ?? 0,group:nil)
        }.frame(minWidth:420)
    }
}

@MainActor struct FindingReadNotice<Value: Sendable>: View {
    let state: FindingReadState<Value>
    @Environment(\.locale) private var locale
    var body: some View {
        let language = AppLanguage.preferred(in:[locale.identifier])
        if let error = state.failure { Text(error.text(language:language)).foregroundStyle(.red).textSelection(.enabled) }
        if state.isStale, state.value != nil { Text(AppStrings.text(.findingUIStale,language:language)).font(.caption).foregroundStyle(.secondary) }
        if state.isLoading { ProgressView().controlSize(.small) }
    }
}

@MainActor struct FindingStatsStrip: View {
    let model: FindingScreenModel
    @Environment(\.locale) private var locale
    var body: some View {
        let language = AppLanguage.preferred(in:[locale.identifier]), stats = model.store.stats.value
        VStack(alignment:.leading) {
            HStack {
                counter(.findingUITotal,stats?.total,language); counter(.findingUIPending,stats?.pending,language)
                ForEach(FindingSeverity.allCases,id:\.rawValue) { severity in
                    let value = switch severity { case .critical: stats?.critical; case .high: stats?.high; case .medium: stats?.medium; case .low: stats?.low }
                    VStack(alignment:.leading) {
                        Text(DashboardLabels.text(severity.rawValue,domain:.severity,language:language)).font(.caption).foregroundStyle(.secondary)
                        Text(value.map(String.init) ?? "—").font(.title3.monospacedDigit())
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }
            }
            FindingReadNotice(state:model.store.stats)
        }
    }
    private func counter(_ key: AppStringKey,_ value: Int64?,_ language: AppLanguage) -> some View {
        VStack(alignment:.leading) { Text(AppStrings.text(key,language:language)).font(.caption).foregroundStyle(.secondary); Text(value.map(String.init) ?? "—").font(.title3.monospacedDigit()) }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
