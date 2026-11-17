import NetworkPNTRCore
import SwiftUI

@MainActor struct FindingFilterBar: View {
    let model: FindingScreenModel
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in:[locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key,language:language) }
    var body: some View {
        let owner = model.store.viewOwner, ticket = model.searchTicket
        VStack(alignment:.leading,spacing:8) {
            searchField(owner:owner)
            HStack {
                severityPicker(owner:owner); statusPicker(owner:owner); sortPicker(owner:owner)
            }
            HStack { classPicker(owner:owner); taskPicker(owner:owner) }
        }.disabled(!model.controlsAvailable)
        .task(id:ticket) {
            guard ticket.enabled else { return }
            do { try await Task.sleep(for:.milliseconds(300)); try Task.checkCancellation(); _ = model.commitSearch(ticket) } catch { }
        }
    }
    private func searchField(owner: UUID) -> some View {
        TextField(s(.findingUISearch),text:Binding(get:{model.searchDraft},set:{if model.store.viewOwner == owner, model.controlsAvailable { model.searchDraft = $0 }}))
            .textFieldStyle(.roundedBorder).accessibilityLabel(s(.findingUISearch)).onSubmit { _ = model.commitSearch(model.searchTicket) }
    }
    private func severityPicker(owner: UUID) -> some View {
        Picker(s(.findingUISeverity),selection:FindingBindings.filter(model,owner:owner,get:{$0.severity?.rawValue ?? "all"},set:{$0.severity = FindingSeverity(rawValue:$1)})) {
            Text(s(.findingUIAll)).tag("all")
            ForEach(FindingSeverity.allCases,id:\.rawValue) { Text(DashboardLabels.text($0.rawValue,domain:.severity,language:language)).tag($0.rawValue) }
        }
    }
    private func statusPicker(owner: UUID) -> some View {
        Picker(s(.findingUIStatus),selection:FindingBindings.filter(model,owner:owner,get:{$0.status?.rawValue ?? "all"},set:{$0.status = FindingStatus(rawValue:$1)})) {
            Text(s(.findingUIAll)).tag("all")
            ForEach(FindingStatus.allCases,id:\.rawValue) { Text(FindingPresentation.status($0.rawValue,language:language)).tag($0.rawValue) }
        }
    }
    private func sortPicker(owner: UUID) -> some View {
        Picker(s(.findingUISort),selection:FindingBindings.filter(model,owner:owner,get:{$0.sort.rawValue},set:{$0.sort = FindingSort(rawValue:$1) ?? .severity})) {
            Text(s(.findingUISeverity)).tag("severity"); Text(s(.findingUITime)).tag("time")
        }
    }
    private func classPicker(owner: UUID) -> some View {
        Picker(s(.findingUIClass),selection:classBinding(owner:owner)) {
            Text(s(.findingUIAll)).tag(Data("all".utf8))
            ForEach(classes,id:\.self) { value in Text(String(decoding:value,as:UTF8.self)).tag(value) }
        }
    }
    private func classBinding(owner: UUID) -> Binding<Data> {
        Binding(get:{Data(model.store.filters.vulnclass.utf8)},set:{value in
            guard model.store.viewOwner == owner, model.controlsAvailable else { return }
            var query = model.store.filters; query.vulnclass = String(decoding:value,as:UTF8.self); query.search = model.searchDraft; _ = model.configureFilters(query)
        })
    }
    private func taskPicker(owner: UUID) -> some View {
        Picker(s(.findingUITask),selection:FindingBindings.filter(model,owner:owner,get:{$0.task},set:{$0.task = $1})) {
            Text(s(.findingUIAll)).tag("all"); Text(s(.findingUIOrphan)).tag("__unassigned__")
            if missingTask { Text("#"+model.store.filters.task).tag(model.store.filters.task) }
            ForEach(model.store.stats.value?.tasks ?? []) { task in Text(taskTitle(task)).tag(task.id) }
        }
    }
    private var missingTask: Bool {
        let selected = model.store.filters.task
        return selected != "all" && selected != "__unassigned__" && model.store.stats.value?.tasks.contains(where:{$0.id == selected}) != true
    }
    private func taskTitle(_ task: FindingTaskOption) -> String {
        let fallback = task.description.isEmpty ? "#"+task.id : task.description
        return (task.name.isEmpty ? fallback : task.name)+" ("+String(task.count)+")"
    }
    private var classes: [Data] {
        var seen = Set<Data>(), result: [Data] = []
        for value in [model.store.filters.vulnclass]+(model.store.stats.value?.vulnclasses ?? []) where value != "all" {
            let bytes = Data(value.utf8); if seen.insert(bytes).inserted { result.append(bytes) }
        }
        return result
    }
}
