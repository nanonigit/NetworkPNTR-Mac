import NetworkPNTRCore
import SwiftUI

@MainActor struct FindingTable: View {
    let model: FindingScreenModel
    let rows: [FindingRecord]
    let loaded: Bool
    let loading: Bool
    let onTask: (String) -> Void
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in:[locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key,language:language) }
    var body: some View {
        let owner = model.store.viewOwner
        Table(rows) {
            TableColumn(s(.findingUISelectPage)) { row in
                if let id = row.findingId {
                    Toggle(AppStrings.formatted(.findingUISelect,language:language,values:["id":id]),isOn:FindingBindings.selected(model,id:id,owner:owner)).labelsHidden().disabled(!model.controlsAvailable)
                }
            }.width(34)
            TableColumn(s(.findingUISeverity)) { row in Text(DashboardLabels.text(row.severity,domain:.severity,language:language)) }.width(min:65,ideal:80)
            TableColumn(s(.findingUIName)) { row in
                Button { if let id = row.findingId { Task { await model.selectDetail(id:id,owner:owner) } } } label: {
                    VStack(alignment:.leading) { Text(row.name.isEmpty ? "#"+row.id : row.name).lineLimit(2); Text(row.vulnclass).font(.caption).foregroundStyle(.secondary) }
                }.buttonStyle(.plain).disabled(!model.controlsAvailable || row.findingId == nil)
            }.width(min:150,ideal:220)
            TableColumn(s(.findingUIAssets)) { row in Text(row.assets.map(\.label).joined(separator:", ")).lineLimit(2) }.width(min:100,ideal:140)
            TableColumn(s(.findingUIStatus)) { row in Text(FindingPresentation.status(row.status,language:language)) }.width(min:80,ideal:100)
            TableColumn(s(.findingUITask)) { row in
                if let id = row.taskId { Button("#"+id) { if model.store.viewOwner == owner, model.controlsAvailable { onTask(id) } }.help(AppStrings.formatted(.findingUIOpenTask,language:language,values:["id":id])) }
                else { Text(s(.findingUIOrphan)).foregroundStyle(.secondary) }
            }.width(min:70,ideal:90)
            TableColumn(s(.findingUITime)) { row in Text(FindingPresentation.time(row.ts,language:language)).font(.caption).textSelection(.enabled) }.width(min:100,ideal:150)
            TableColumn(s(.findingUIActions)) { row in
                Menu(s(.findingUIActions)) {
                    Button(s(.findingUIEdit)) { if model.store.viewOwner == owner { _ = model.beginEdit(row) } }
                    Menu(s(.findingUIStatus)) { ForEach(FindingStatus.allCases,id:\.rawValue) { status in Button(FindingPresentation.status(status.rawValue,language:language)) { if model.store.viewOwner == owner { _ = model.beginStatus(row,status:status) } }.disabled(status.rawValue == row.status) } }
                    Button(s(.findingUIDelete),role:.destructive) { if model.store.viewOwner == owner { _ = model.beginDelete(row) } }
                }.disabled(!model.controlsAvailable || !row.canMutate || model.hasUnknownWrites)
            }.width(90)
        }
        .overlay { if rows.isEmpty, loaded, !loading { Text(s(.findingUIEmpty)).foregroundStyle(.secondary).padding() } }
    }
}

@MainActor struct FindingPager: View {
    let model: FindingScreenModel
    let page: Int64
    let size: Int
    let total: Int64
    let group: String?
    @Environment(\.locale) private var locale
    var body: some View {
        let language = AppLanguage.preferred(in:[locale.identifier]), owner = model.store.viewOwner
        let pages = FindingPresentation.pages(total:total,size:size)
        HStack {
            Text(AppStrings.formatted(.findingUIPage,language:language,values:["page":String(page),"pages":String(pages),"total":String(total)])).font(.caption).monospacedDigit()
            Spacer()
            Picker(AppStrings.text(.findingUIPageSize,language:language),selection:Binding(get:{size},set:{_ = model.page(page:1,size:$0,owner:owner,group:group)})) { ForEach([10,20,50,100],id:\.self) { Text(String($0)).tag($0) } }.fixedSize()
            Button(AppStrings.text(.findingUIPrevious,language:language)) { _ = model.page(page:page-1,size:size,owner:owner,group:group) }.disabled(page <= 1)
            Button(AppStrings.text(.findingUINext,language:language)) { if page < pages { _ = model.page(page:page+1,size:size,owner:owner,group:group) } }.disabled(page >= pages)
        }.disabled(!model.controlsAvailable)
    }
}
