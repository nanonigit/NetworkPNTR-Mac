import ArtexCore
import SwiftUI

@MainActor enum TaskTemplateBindings {
    static func field<Value>(model: TaskTemplateManager, contextID: UUID, editorID: UUID, key: WritableKeyPath<TaskTemplateForm, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { model.context?.id == contextID && model.editorID == editorID ? model.form[keyPath:key] : fallback },
                set: { model.update(key,value:$0,contextID:contextID,editorID:editorID) })
    }
    static func rule<Value>(model: TaskTemplateManager, contextID: UUID, editorID: UUID, ruleID: UUID, key: WritableKeyPath<TaskInterceptRuleDraft, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { model.context?.id == contextID && model.editorID == editorID ? model.form.rules.first(where: { $0.id == ruleID })?.rule[keyPath:key] ?? fallback : fallback },
                set: { model.updateRule(id:ruleID,key:key,value:$0,contextID:contextID,editorID:editorID) })
    }
}

@MainActor struct TaskTemplateManagerView: View {
    let model: TaskTemplateManager
    let contextID: UUID
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in:[locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key,language:language) }
    private var blocked: Bool { model.isMutating || model.uncertain || model.pendingDecision != nil }
    var body: some View {
        let editor = model.editorID
        let decision = model.pendingDecision
        VStack(alignment:.leading,spacing:12) {
            Text(s(.taskTemplateTitle)).font(.title2.bold())
            Text(s(.taskTemplateHelp)).foregroundStyle(.secondary)
            HStack(alignment:.top,spacing:18) {
                VStack {
                    TextField(s(.taskTemplateSearch),text:Binding(get:{model.query},set:{model.setQuery($0,contextID:contextID)}))
                    ScrollView {
                        VStack(alignment:.leading) {
                            ForEach(model.templates.filter { model.query.isEmpty || $0.name.localizedCaseInsensitiveContains(model.query) }) { row in
                                Button { model.requestSelection(row.id,contextID:contextID,editorID:editor) } label: {
                                    HStack { Text(row.name).lineLimit(2); Spacer(); if model.selectedID == row.id { Image(systemName:"checkmark") } }.frame(maxWidth:.infinity,alignment:.leading)
                                }.buttonStyle(.borderless).padding(6)
                            }
                            if model.templates.isEmpty { Text(s(.taskTemplateEmpty)).foregroundStyle(.secondary) }
                        }
                    }
                    Button(s(.taskTemplateNew),systemImage:"plus") { model.requestSelection(nil,contextID:contextID,editorID:editor) }
                    Button(s(.taskCreateOptionsRefresh),systemImage:"arrow.clockwise") { Task { await model.load(contextID:contextID) } }.disabled(model.isLoading)
                }.frame(width:200).disabled(blocked)
                Divider()
                ScrollView {
                    VStack(alignment:.leading,spacing:12) {
                        TextField(s(.taskUIName),text:field(\.name,"",editor))
                        Text(s(.taskUIDescription)).font(.headline)
                        TextEditor(text:field(\.description,"",editor)).frame(minHeight:100).border(.quaternary)
                        Text(s(.taskUIGoal)).font(.headline)
                        TextEditor(text:field(\.goal,"",editor)).frame(minHeight:100).border(.quaternary)
                        Picker(s(.taskUICategory),selection:field(\.categoryId,nil,editor)) {
                            Text(s(.taskUIUncategorized)).tag(Optional<Int64>.none)
                            ForEach(model.categories) { Text($0.name).tag(Optional($0.id)) }
                            if let id = model.form.categoryId, !model.categories.contains(where:{$0.id == id}) {
                                Text(AppStrings.formatted(.taskCreateUnavailable,language:language,values:["id":String(id)])).tag(Optional(id))
                            }
                        }
                        GroupBox(s(.taskCreateRules)) {
                            VStack {
                                ForEach(model.form.rules) { row in
                                    TaskRuleEditorRow(enabled:rule(\.enabled,false,row.id,editor),action:rule(\.action,.block,row.id,editor),kind:rule(\.kind,.exactDomain,row.id,editor),pattern:rule(\.pattern,"",row.id,editor),note:rule(\.note,"",row.id,editor)) { model.removeRule(id:row.id,contextID:contextID,editorID:editor) }
                                }
                                Button(s(.taskCreateAddRule),systemImage:"plus") { model.addRule(contextID:contextID,editorID:editor) }
                            }
                        }
                    }.textFieldStyle(.roundedBorder).disabled(blocked)
                }
            }
            if let error = model.listFailure { Text(error.text(language:language)).foregroundStyle(.red) }
            if let error = model.categoryFailure { Text(error.text(language:language)).foregroundStyle(.red) }
            if model.uncertain {
                Text(s(.taskTemplateUnknown)).foregroundStyle(.orange)
                Button(s(.taskTemplateLocalDiscard)) { model.requestLocalDiscard(contextID:contextID) }.disabled(model.isMutating || decision != nil)
            } else if let error = model.failure { Text(error.text(language:language)).foregroundStyle(.red) }
            Divider()
            HStack {
                Button(s(.taskTemplateDelete),role:.destructive) { model.requestDelete(contextID:contextID,editorID:editor) }.disabled(blocked || model.selectedID == nil)
                Spacer()
                if model.isLoading || model.isMutating { ProgressView().controlSize(.small) }
                Button(s(.taskUIClose)) { model.close(contextID:contextID) }.disabled(model.isMutating || decision != nil).keyboardShortcut(.cancelAction)
                Button(s(model.selectedID == nil ? .taskTemplateCreate : .taskTemplateSave)) { Task { _ = await model.save(contextID:contextID,editorID:editor) } }.disabled(blocked || model.isLoading).keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width:800,height:650)
        .alert(s(decision?.isDelete == true ? .taskTemplateDeleteTitle : .taskTemplateDirtyTitle),isPresented:Binding(get:{model.context?.id == contextID && model.pendingDecision != nil},set:{if !$0, let decision { model.resolveDecisionFromUI(id:decision.id,confirm:false,contextID:contextID) }}),presenting:decision) { value in
            Button(s(.taskUICancel),role:.cancel) { model.resolveDecisionFromUI(id:value.id,confirm:false,contextID:contextID) }
            Button(s(value.isDelete ? .taskTemplateDelete : .taskTemplateDiscard),role:.destructive) { model.resolveDecisionFromUI(id:value.id,confirm:true,contextID:contextID) }
        } message: { value in
            Text(s(value.isDelete ? .taskTemplateDeleteHelp : value.isLocalDiscard ? .taskTemplateLocalHelp : .taskTemplateDirtyHelp) + (value.name.map { "\n" + $0 } ?? ""))
        }
        .interactiveDismissDisabled(model.isMutating || decision != nil)
        .task { await model.load(contextID:contextID) }
    }
    private func field<Value>(_ key: WritableKeyPath<TaskTemplateForm,Value>, _ fallback: Value, _ editor: UUID) -> Binding<Value> {
        TaskTemplateBindings.field(model:model,contextID:contextID,editorID:editor,key:key,fallback:fallback)
    }
    private func rule<Value>(_ key: WritableKeyPath<TaskInterceptRuleDraft,Value>, _ fallback: Value, _ id: UUID, _ editor: UUID) -> Binding<Value> {
        TaskTemplateBindings.rule(model:model,contextID:contextID,editorID:editor,ruleID:id,key:key,fallback:fallback)
    }
}
