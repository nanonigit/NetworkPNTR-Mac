import ArtexCore
import SwiftUI

@MainActor struct FindingFilterBar: View {
    let model: FindingScreenModel
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in:[locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key,language:language) }
    var body: some View {
        let owner = model.store.viewOwner
        VStack(alignment:.leading,spacing:8) {
            TextField(s(.findingUISearch),text:Binding(get:{model.searchDraft},set:{if model.store.viewOwner == owner, model.controlsAvailable { model.searchDraft = $0 }}))
                .textFieldStyle(.roundedBorder).accessibilityLabel(s(.findingUISearch)).onSubmit { search(owner:owner) }
            HStack {
                Picker(s(.findingUISeverity),selection:FindingBindings.filter(model,owner:owner,get:{$0.severity?.rawValue ?? "all"},set:{$0.severity = FindingSeverity(rawValue:$1)})) {
                    Text(s(.findingUIAll)).tag("all")
                    ForEach(FindingSeverity.allCases,id:\.rawValue) { Text(DashboardLabels.text($0.rawValue,domain:.severity,language:language)).tag($0.rawValue) }
                }
                Picker(s(.findingUIStatus),selection:FindingBindings.filter(model,owner:owner,get:{$0.status?.rawValue ?? "all"},set:{$0.status = FindingStatus(rawValue:$1)})) {
                    Text(s(.findingUIAll)).tag("all")
                    ForEach(FindingStatus.allCases,id:\.rawValue) { Text(FindingPresentation.status($0.rawValue,language:language)).tag($0.rawValue) }
                }
                Picker(s(.findingUISort),selection:FindingBindings.filter(model,owner:owner,get:{$0.sort.rawValue},set:{$0.sort = FindingSort(rawValue:$1) ?? .severity})) {
                    Text(s(.findingUISeverity)).tag("severity"); Text(s(.findingUITime)).tag("time")
                }
            }
            HStack {
                Picker(s(.findingUIClass),selection:Binding(get:{Data(model.store.filters.vulnclass.utf8)},set:{value in
                    guard model.store.viewOwner == owner, model.controlsAvailable else { return }
                    var query = model.store.filters; query.vulnclass = String(decoding:value,as:UTF8.self); query.search = model.searchDraft; _ = model.configureFilters(query)
                })) {
                    Text(s(.findingUIAll)).tag(Data("all".utf8))
                    ForEach(classes,id:\.self) { value in Text(String(decoding:value,as:UTF8.self)).tag(value) }
                }
                Picker(s(.findingUITask),selection:FindingBindings.filter(model,owner:owner,get:{$0.task},set:{$0.task = $1})) {
                    Text(s(.findingUIAll)).tag("all"); Text(s(.findingUIOrphan)).tag("__unassigned__")
                    if model.store.filters.task != "all", model.store.filters.task != "__unassigned__", model.store.stats.value?.tasks.contains(where:{$0.id == model.store.filters.task}) != true { Text("#"+model.store.filters.task).tag(model.store.filters.task) }
                    ForEach(model.store.stats.value?.tasks ?? []) { task in Text((task.name.isEmpty ? (task.description.isEmpty ? "#"+task.id : task.description) : task.name)+" ("+String(task.count)+")").tag(task.id) }
                }
            }
        }.disabled(!model.controlsAvailable)
        .task(id:Data(model.searchDraft.utf8)) {
            do { try await Task.sleep(for:.milliseconds(300)); try Task.checkCancellation(); search(owner:owner) } catch { }
        }
    }
    private var classes: [Data] {
        var seen = Set<Data>(), result: [Data] = []
        for value in [model.store.filters.vulnclass]+(model.store.stats.value?.vulnclasses ?? []) where value != "all" {
            let bytes = Data(value.utf8); if seen.insert(bytes).inserted { result.append(bytes) }
        }
        return result
    }
    private func search(owner: UUID) {
        guard model.controlsAvailable, model.store.viewOwner == owner else { return }
        var query = model.store.filters; query.search = model.searchDraft
        if !query.search.utf8.elementsEqual(model.store.filters.search.utf8) { _ = model.configureFilters(query) }
    }
}
