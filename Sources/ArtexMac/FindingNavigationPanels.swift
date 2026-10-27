import ArtexCore
import SwiftUI

@MainActor struct FindingAssetPanel: View {
    let model: FindingScreenModel
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in:[locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key,language:language) }
    var body: some View {
        let owner = model.store.viewOwner
        VStack(alignment:.leading) {
            Text(s(.findingUIAssets)).font(.headline)
            FindingReadNotice(state:model.store.tree)
            if model.store.tree.value?.truncated == true { Text(s(.findingUITreeTruncated)).font(.caption).foregroundStyle(.secondary) }
            Button(s(.findingUIAll)) { _ = model.asset(nil,owner:owner) }.disabled(!model.controlsAvailable)
            List {
                if let tree = model.store.tree.value {
                    ForEach(FindingPresentation.assetRows(tree,expanded:model.expandedAssets)) { row in
                        HStack(spacing:6) {
                            if row.hasChildren {
                                Button {
                                    guard model.store.viewOwner == owner, model.controlsAvailable else { return }
                                    if !model.expandedAssets.insert(row.id).inserted { model.expandedAssets.remove(row.id) }
                                } label: { Image(systemName:model.expandedAssets.contains(row.id) ? "chevron.down" : "chevron.right") }
                                    .buttonStyle(.plain).accessibilityLabel(row.node.label).accessibilityValue(String(model.expandedAssets.contains(row.id)))
                            }
                            Button { _ = model.asset(row.node.key,owner:owner) } label: {
                                HStack { Text(row.node.label).lineLimit(2); Spacer(); Text(String(row.node.total)).monospacedDigit().foregroundStyle(.secondary) }
                            }.buttonStyle(.plain).foregroundStyle(model.store.assetScope.map{Data($0.utf8)} == row.id ? Color.accentColor : Color.primary)
                        }.padding(.leading,CGFloat(min(row.depth,12))*12).disabled(!model.controlsAvailable)
                    }
                }
            }.listStyle(.sidebar)
        }
    }
}

@MainActor struct FindingGroupsPanel: View {
    let model: FindingScreenModel
    let onTask: (String) -> Void
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in:[locale.identifier]) }
    var body: some View {
        let owner = model.store.viewOwner
        VStack(alignment:.leading) {
            FindingReadNotice(state:model.store.groups.read)
            ScrollView {
                LazyVStack(alignment:.leading,spacing:12) {
                    ForEach(model.store.groups.read.value?.items ?? [],id:\.taskId) { group in
                        let key = group.taskId ?? "__unassigned__"
                        DisclosureGroup(isExpanded:Binding(get:{model.store.expandedGroups.contains(key)},set:{value in
                            guard model.controlsAvailable else { return }; Task { await model.store.setGroupExpanded(key,expanded:value,owner:owner) }
                        })) {
                            if let state = model.store.groupPages[key] {
                                FindingReadNotice(state:state.read)
                                FindingTable(model:model,rows:state.read.value?.items ?? [],onTask:onTask).frame(height: min(500,CGFloat(max(1,state.read.value?.items.count ?? 0))*48+40))
                                FindingPager(model:model,page:state.page,size:state.size,total:state.read.value?.total ?? group.count,group:key)
                            }
                        } label: {
                            HStack {
                                Text(title(group)).font(.headline).lineLimit(2)
                                if !group.taskStatus.isEmpty { Text(DashboardLabels.text(group.taskStatus,domain:.task,language:language)).font(.caption).foregroundStyle(.secondary) }
                                Spacer(); Text(String(group.count)).monospacedDigit()
                            }
                        }
                    }
                    if model.store.groups.read.value?.items.isEmpty == true { Text(AppStrings.text(.findingUIEmpty,language:language)).foregroundStyle(.secondary) }
                }.padding(4)
            }
            FindingPager(model:model,page:model.store.groups.page,size:model.store.groups.size,total:model.store.groups.read.value?.total ?? 0,group:nil)
        }
    }
    private func title(_ group: FindingGroup) -> String {
        guard let id = group.taskId else { return AppStrings.text(.findingUIOrphan,language:language) }
        if !group.taskName.isEmpty { return group.taskName }; if !group.taskDescription.isEmpty { return group.taskDescription }; return "#"+id
    }
}
