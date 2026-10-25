import ArtexCore
import SwiftUI

@MainActor enum TaskCategoryBindings {
    static func name(model: TaskCategoryWorkspace, contextID: UUID, editorID: UUID) -> Binding<String> {
        Binding(get:{model.context?.id == contextID && model.editorID == editorID ? model.name : ""},set:{model.setName($0,contextID:contextID,editorID:editorID)})
    }
    static func presentation(model: TaskCategoryWorkspace, contextID: UUID?, inlineOwner: UUID? = nil) -> Binding<TaskCategoryContext?> {
        Binding(get:{model.context?.inlineOwner == inlineOwner ? model.context : nil},set:{if $0 == nil, model.context?.inlineOwner == inlineOwner, let contextID { model.close(contextID:contextID) }})
    }
}

@MainActor struct TaskCategoryView: View {
    let model: TaskCategoryWorkspace
    let contextID: UUID
    @State private var moveTarget: Int64?
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in:[locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key,language:language) }
    private func f(_ key: AppStringKey,_ values: [String:String]) -> String { AppStrings.formatted(key,language:language,values:values) }
    private var blocked: Bool { model.isMutating || model.uncertain || model.decision != nil }
    var body: some View {
        let editor = model.editorID
        let decision = model.decision
        let inline = model.context?.inlineOwner != nil
        VStack(alignment:.leading,spacing:12) {
            Text(s(inline ? .taskCategoryUIInline : .taskCategoryUITitle)).font(.title2.bold())
            if !inline { Text(s(.taskCategoryUIHelp)).foregroundStyle(.secondary) }
            HStack(alignment:.top,spacing:16) {
                if !inline { sidebar(editor:editor).frame(width:210).disabled(blocked); Divider() }
                VStack(alignment:.leading,spacing:12) {
                    if model.selection != .uncategorized {
                        TextField(s(.taskUIName),text:TaskCategoryBindings.name(model:model,contextID:contextID,editorID:editor)).textFieldStyle(.roundedBorder).disabled(blocked)
                    } else { Text(s(.taskUIUncategorized)).font(.headline) }
                    if !inline { taskList(editor:editor) }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            if let failure = model.categoryFailure { Text(failure.text(language:language)).foregroundStyle(.red) }
            if let failure = model.taskFailure, !inline { Text(failure.text(language:language)).foregroundStyle(.red) }
            if model.countsStale, !inline { Text(s(.taskUIStale)).font(.caption).foregroundStyle(.secondary) }
            if model.uncertain {
                Text(s(.taskCategoryUIUnknown)).foregroundStyle(.orange)
                Button(s(.taskCategoryUILocalDiscard)) { model.requestDiscard(contextID:contextID) }.disabled(model.isMutating || decision != nil)
            } else if let error = model.failure { Text(error.text(language:language)).foregroundStyle(.red) }
            else if let change = model.lastChange {
                if case .batchAssigned(let result) = change {
                    Text(f(.taskCategoryUIPartial,["ok":String(result.items.filter(\.ok).count),"failed":String(result.items.filter{!$0.ok}.count)]))
                } else { Text(s(.taskCategoryUIResult)).foregroundStyle(.secondary) }
            }
            Spacer(minLength:0); Divider()
            HStack {
                if case .category = model.selection, !inline {
                    Button(s(.taskCategoryUIDelete),role:.destructive) { model.requestDelete(contextID:contextID,editorID:editor) }.disabled(blocked)
                }
                Button(s(.taskUIRefresh),systemImage:"arrow.clockwise") { Task { await model.load(contextID:contextID) } }.disabled(model.isLoading || model.isMutating)
                Spacer()
                if model.isMutating || model.isLoading { ProgressView().controlSize(.small) }
                Button(s(.taskUIClose)) { model.close(contextID:contextID) }.keyboardShortcut(.cancelAction).disabled(model.isMutating || decision != nil)
                if model.selection != .uncategorized {
                    Button(s(model.selection == .new ? .taskCategoryUICreate : .taskCategoryUISave)) { Task { _ = await model.save(contextID:contextID,editorID:editor) } }
                        .keyboardShortcut(.defaultAction).disabled(blocked || model.isLoading || ChatText.trim(model.name).isEmpty)
                }
            }
        }.padding(20).frame(width:inline ? 560 : 820,height:inline ? 300 : 650)
        .alert(s(decision?.isDelete == true ? .taskCategoryUIDeleteTitle : decision?.isMove == true ? .taskCategoryUIMoveTitle : .taskCategoryUIDirtyTitle),isPresented:Binding(get:{model.context?.id == contextID && model.decision != nil},set:{if !$0, let decision { model.resolveFromUI(id:decision.id,accept:false,contextID:contextID) }}),presenting:decision) { value in
            Button(s(.taskUICancel),role:.cancel) { model.resolveFromUI(id:value.id,accept:false,contextID:contextID) }
            Button(s(value.isDelete ? .taskCategoryUIDelete : value.isMove ? .taskCategoryUIMove : .taskCategoryUIDiscard),role:value.isMove ? nil : .destructive) { model.resolveFromUI(id:value.id,accept:true,contextID:contextID) }
        } message: { value in
            if value.isDelete { Text(f(.taskCategoryUIDeleteHelp,["name":value.name ?? "","count":String(value.deleteCount)])) }
            else if value.isMove { Text(f(.taskCategoryUIMoveHelp,["count":String(value.taskIDs.count),"target":value.targetName ?? s(.taskUIUncategorized)])) }
            else { Text(s(value.isDiscard ? .taskCategoryUILocalHelp : .taskCategoryUIDirtyHelp)) }
        }
        .interactiveDismissDisabled(model.isMutating || decision != nil)
        .task { await model.load(contextID:contextID) }
    }
    private func sidebar(editor: UUID) -> some View {
        ScrollView {
            VStack(alignment:.leading,spacing:10) {
                Button(s(.taskCategoryUINew),systemImage:"plus") { model.select(.new,contextID:contextID,editorID:editor) }
                targetButton(s(.taskUIUncategorized),selection:.uncategorized,target:nil,editor:editor)
                ForEach(model.categories) { category in
                    targetButton(f(.taskCategoryUICount,["name":category.name,"count":String(category.taskCount)]),selection:.category(category.id),target:category.id,editor:editor)
                }
            }.frame(maxWidth:.infinity,alignment:.leading)
        }
    }
    private func targetButton(_ label: String, selection: TaskCategorySelection, target: Int64?, editor: UUID) -> some View {
        Button { model.select(selection,contextID:contextID,editorID:editor) } label: {
            HStack { Text(label); Spacer(); if model.selection == selection { Image(systemName:"checkmark") } }.frame(maxWidth:.infinity,alignment:.leading)
        }.buttonStyle(.borderless).padding(5)
        .dropDestination(for:String.self) { items,_ in
            guard items.count == 1, let value = items.first, value.hasPrefix("artex-task:") else { return false }
            let id = String(value.dropFirst("artex-task:".count))
            model.requestMove(ids:[id],target:target,contextID:contextID,editorID:editor)
            return model.decision?.isMove == true
        }
    }
    private func taskList(editor: UUID) -> some View {
        VStack(alignment:.leading,spacing:10) {
            Text(s(.taskCategoryUITasks)).font(.headline)
            HStack {
                Text(f(.taskCategoryUISelected,["count":String(model.selectedTaskIDs.count)])).font(.caption)
                Picker(s(.taskCategoryUITarget),selection:$moveTarget) {
                    Text(s(.taskUIUncategorized)).tag(Optional<Int64>.none)
                    ForEach(model.categories) { Text($0.name).tag(Optional($0.id)) }
                    if let id = moveTarget, !model.categories.contains(where:{$0.id == id}) { Text("#\(id)").tag(Optional(id)) }
                }
                Button(s(.taskCategoryUIMove)) { model.requestMove(ids:model.visibleTasks.filter { model.selectedTaskIDs.contains($0.id) }.map(\.id),target:moveTarget,contextID:contextID,editorID:editor) }.disabled(model.selectedTaskIDs.isEmpty || moveTarget.map { id in !model.categories.contains(where:{$0.id == id}) } == true)
            }.disabled(blocked)
            ScrollView {
                VStack(alignment:.leading,spacing:10) {
                    ForEach(model.visibleTasks) { task in
                        HStack {
                            Toggle(isOn:Binding(get:{model.selectedTaskIDs.contains(task.id)},set:{model.selectTask(task.id,selected:$0,contextID:contextID,editorID:editor)})) {
                                VStack(alignment:.leading) {
                                    Text("#\(task.id) · " + (task.name.isEmpty ? task.description : task.name)).lineLimit(2)
                                    Text(DashboardLabels.text(task.status,domain:.task,language:language)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Menu(s(.taskCategoryUIMove)) {
                                Button(s(.taskUIUncategorized)) { model.requestMove(ids:[task.id],target:nil,contextID:contextID,editorID:editor) }
                                ForEach(model.categories) { target in
                                    Button(target.name) { model.requestMove(ids:[task.id],target:target.id,contextID:contextID,editorID:editor) }
                                }
                            }.menuStyle(.borderlessButton).frame(width:100)
                        }.padding(6).draggable("artex-task:"+task.id).disabled(blocked)
                    }
                    if model.visibleTasks.isEmpty { Text(s(.taskCategoryUINoTasks)).foregroundStyle(.secondary) }
                }
            }
        }
    }
}
