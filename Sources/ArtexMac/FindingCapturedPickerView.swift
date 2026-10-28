import ArtexCore
import SwiftUI

@MainActor struct FindingCapturedPickerSheet: View {
    let picker: FindingCapturedPicker
    let close: () -> Void
    var body: some View {
        FindingCapturedPickerContent(picker:picker,close:close)
            .task(id:picker.filterTicket) { await picker.debounce(picker.filterTicket) }
            .onDisappear { picker.stop() }
    }
}

@MainActor struct FindingCapturedPickerContent: View {
    let picker: FindingCapturedPicker
    let close: () -> Void
    @State private var side: FindingEvidenceSide = .request
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in:[locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key,language:language) }
    var body: some View {
        let owner = picker.store.owner
        VStack(alignment:.leading,spacing:12) {
            Text(s(.capturedUITitle)).font(.title2.bold())
            Text(s(.capturedUIHelp)).foregroundStyle(.secondary)
            HStack(alignment:.top) {
                VStack(alignment:.leading) {
                    Text(s(.capturedUIHost)).font(.caption)
                    TextField(s(.capturedUIHost),text:FindingCapturedPickerBindings.draft(picker,key:\.hostDraft)).textFieldStyle(.roundedBorder)
                }
                VStack(alignment:.leading) {
                    Text(s(.capturedUIMethod)).font(.caption)
                    Picker(s(.capturedUIMethod),selection:FindingCapturedPickerBindings.method(picker)) {
                        Text(s(.findingUIAll)).tag("")
                        ForEach(CapturedHTTPMethod.allCases,id:\.rawValue) { Text(verbatim:$0.rawValue).tag($0.rawValue) }
                    }.labelsHidden()
                }.frame(width:140)
                VStack(alignment:.leading) {
                    Text(s(.capturedUIKeyword)).font(.caption)
                    TextField(s(.capturedUIKeyword),text:FindingCapturedPickerBindings.draft(picker,key:\.keywordDraft)).textFieldStyle(.roundedBorder)
                }
            }.disabled(!picker.canEditFilters)
            HStack {
                if picker.store.catalog.isLoading || !picker.filtersCurrent { ProgressView().controlSize(.small) }
                FindingReadNotice(state:picker.store.catalog)
                Spacer()
                Button(s(.findingUIRefresh),systemImage:"arrow.clockwise") { Task { await picker.reload(owner:owner) } }
                    .disabled(!picker.canEditFilters || !picker.filtersCurrent || picker.store.catalog.isLoading)
            }
            if let failure = picker.failure ?? picker.store.failure { Text(failure.text(language:language)).foregroundStyle(.red).textSelection(.enabled) }
            if picker.hasUnknownOutcome { Text(s(.evidenceUIUnknownHelp)).foregroundStyle(.orange) }
            VSplitView {
                candidates(owner:owner).frame(minHeight:160)
                rawPreview(owner:owner).frame(minHeight:150)
            }
            HStack {
                Text(AppStrings.formatted(.capturedUISelected,language:language,values:["count":String(picker.store.selectedCount),"total":String(picker.store.catalog.value?.total ?? 0)]))
                Button(s(.findingUIClear)) { _ = picker.clearSelection(owner:owner) }.disabled(!picker.canEditFilters || picker.store.selectedCount == 0)
                Spacer()
                Button(s(.capturedUIPrevious)) { Task { await picker.page(forward:false,owner:owner) } }.disabled(!picker.canSelect || !picker.store.hasPrevious)
                Text(AppStrings.formatted(.capturedUIPage,language:language,values:["page":String(picker.store.query.page+1)])).font(.caption.monospacedDigit())
                Button(s(.capturedUINext)) { Task { await picker.page(forward:true,owner:owner) } }.disabled(!picker.canSelect || !picker.store.hasNext)
            }
            HStack {
                if picker.isSubmitting { ProgressView().controlSize(.small); Text(s(.capturedUIBinding)) }
                Spacer()
                Button(s(.findingUICancel),action:close).keyboardShortcut(.cancelAction).disabled(picker.isSubmitting)
                Button(AppStrings.formatted(.capturedUIAddCount,language:language,values:["count":String(picker.store.selectedCount)])) { Task { _ = await picker.bind(owner:owner) } }
                    .keyboardShortcut(.defaultAction).disabled(!picker.canBind)
            }
        }
        .padding(20).frame(minWidth:840,idealWidth:1040,minHeight:600,idealHeight:740)
        .interactiveDismissDisabled(picker.isSubmitting)
    }
    private func candidates(owner: UUID) -> some View {
        let rows = picker.store.catalog.value?.exchanges ?? []
        let selectable = rows.filter { !picker.isBound($0.id) }
        return ScrollView([.horizontal,.vertical]) {
            LazyVStack(alignment:.leading,spacing:10) {
                if picker.store.catalog.value?.isUnavailable == true { Text(s(.capturedUIUnavailable)).foregroundStyle(.secondary) }
                else {
                    if picker.store.catalog.value?.enabled == false { Text(s(.capturedUICaptureOff)).foregroundStyle(.secondary) }
                    HStack {
                        Toggle(s(.capturedUISelectPage),isOn:Binding(get:{!selectable.isEmpty && selectable.allSatisfy { picker.isSelected($0.id,owner:owner) }},set:{_ = picker.selectPage($0,owner:owner)}))
                            .toggleStyle(.checkbox).disabled(!picker.canSelect || selectable.isEmpty)
                        Spacer(); Text(s(.capturedUITime)).frame(width:150); Text(s(.capturedUIStatus)).frame(width:55); Text(s(.capturedUIPreview)).frame(width:85)
                    }.font(.caption)
                    ForEach(rows,id:\.identity) { row in
                        HStack(alignment:.top) {
                            Toggle(AppStrings.formatted(.capturedUISelectOne,language:language,values:["id":row.id]),isOn:FindingCapturedPickerBindings.selected(picker,source:row.id,owner:owner))
                                .labelsHidden().toggleStyle(.checkbox).disabled(!picker.canSelect || picker.isBound(row.id))
                                .accessibilityLabel(AppStrings.formatted(.capturedUISelectOne,language:language,values:["id":row.id]))
                            VStack(alignment:.leading,spacing:3) {
                                Text(verbatim:row.method+" "+row.url).font(.system(.caption,design:.monospaced)).textSelection(.enabled)
                                if picker.isBound(row.id) { Text(s(.capturedUIBound)).font(.caption).foregroundStyle(.secondary) }
                            }.frame(maxWidth:.infinity,alignment:.leading)
                            Group {
                                if let date = FindingTrafficPresentation.recordedDate(row.ts) { Text(date,format:.dateTime) }
                                else { Text(verbatim:row.ts) }
                            }.font(.caption).frame(width:150,alignment:.leading)
                            Text(verbatim:String(row.status)).monospacedDigit().frame(width:55)
                            Button(s(.capturedUIPreview)) { Task { await picker.selectPreview(row.id,owner:owner) } }.controlSize(.small).frame(width:85).disabled(!picker.canSelect)
                        }.padding(.vertical,4).accessibilityElement(children:.contain)
                    }
                    if rows.isEmpty, !picker.store.catalog.isLoading { Text(s(.capturedUIEmpty)).foregroundStyle(.secondary) }
                }
            }.frame(minWidth:760,maxWidth:.infinity,alignment:.leading).padding(10)
        }.background(Color.primary.opacity(0.03),in:RoundedRectangle(cornerRadius:6))
    }
    @ViewBuilder private func rawPreview(owner: UUID) -> some View {
        if let id = picker.store.selectedPreviewID {
            VStack(alignment:.leading,spacing:8) {
                HStack {
                    Picker(s(.evidenceUISide),selection:$side) {
                        Text(s(.evidenceUIRequest)).tag(FindingEvidenceSide.request)
                        Text(s(.evidenceUIResponse)).tag(FindingEvidenceSide.response)
                    }.pickerStyle(.segmented)
                    Button(s(.findingUIClose)) { picker.closePreview(id,owner:owner) }.disabled(picker.isSubmitting)
                }
                FindingReadNotice(state:picker.store.preview)
                if let raw = picker.store.preview.value {
                    ScrollView([.horizontal,.vertical]) {
                        Text(verbatim:side == .request ? raw.request : raw.response).font(.system(.caption,design:.monospaced)).textSelection(.enabled)
                            .frame(maxWidth:.infinity,alignment:.leading).padding(10)
                    }
                }
            }
        } else { ContentUnavailableView(s(.capturedUIPreviewHelp),systemImage:"doc.text.magnifyingglass") }
    }
}
