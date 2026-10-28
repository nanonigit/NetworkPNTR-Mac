import ArtexCore
import SwiftUI

@MainActor struct FindingTrafficSheet: View {
    let model: FindingTrafficWorkspace
    let close: () -> Void
    @State private var presenter = EvidenceSavePanelPresenter()
    var body: some View {
        FindingTrafficContent(model:model,presenter:presenter,close:close)
            .task { await model.refresh() }
            .onDisappear { presenter.cancel(); model.stop() }
    }
}

@MainActor struct FindingTrafficContent: View {
    let model: FindingTrafficWorkspace
    let presenter: EvidenceSavePanelPresenter
    let close: () -> Void
    @State private var side: FindingEvidenceSide = .request
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in:[locale.identifier]) }
    private var controlsAvailable: Bool { model.isActive && !model.isReading && !model.isExporting }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key,language:language) }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                VStack(alignment:.leading) { Text(s(.evidenceUITitle)).font(.title2.bold()); Text(verbatim:model.target.name).textSelection(.enabled) }
                Spacer()
                if model.isReading { ProgressView().controlSize(.small).accessibilityLabel(s(.evidenceUILoading)) }
                Button(s(.findingUIRefresh),systemImage:"arrow.clockwise") { Task { await model.refresh() } }.disabled(!controlsAvailable)
                Button(s(.findingUIClose),systemImage:"xmark",action:close).keyboardShortcut(.cancelAction)
            }
            if model.target.inherited { Text(s(.evidenceUIReadOnly)).foregroundStyle(.secondary) }
            FindingReadNotice(state:model.store.summary)
            if let failure = model.failure { Text(failure.text(language:language)).foregroundStyle(.red).textSelection(.enabled) }
            HSplitView {
                evidenceList.frame(minWidth:250,idealWidth:310,maxWidth:390)
                evidenceViewer.frame(minWidth:380,maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            }
            Text(s(.evidenceUIMutationsPending)).font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(minWidth:760,idealWidth:960,minHeight:560,idealHeight:680)
        .background(EvidenceWindowAnchor(presenter:presenter).frame(width:0,height:0))
        .onAppear { presenter.language = language }
        .onChange(of:language) { _,value in presenter.language = value }
        .interactiveDismissDisabled(model.isExporting)
    }
    private var evidenceList: some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:10) {
                if let bindings = model.store.summary.value?.bindings {
                    if bindings.isEmpty { Text(s(.evidenceUIEmpty)).foregroundStyle(.secondary) }
                    ForEach(bindings,id:\.id) { binding in
                        VStack(alignment:.leading,spacing:5) {
                            HStack { Text(verbatim:binding.snapshot.method).bold(); Text(verbatim:String(binding.snapshot.status)); Spacer(); Text(role(binding.role)).font(.caption) }
                            Text(verbatim:binding.snapshot.url).lineLimit(3).textSelection(.enabled)
                            Text(verbatim:binding.note).textSelection(.enabled)
                            Text(AppStrings.formatted(.evidenceUIBindingID,language:language,values:["id":binding.id])).font(.caption).foregroundStyle(.secondary)
                            Text(Date(timeIntervalSince1970:Double(binding.snapshot.capturedAt)/1000),format:.dateTime).font(.caption).foregroundStyle(.secondary)
                            Button(s(.evidenceUIInspect),systemImage:"doc.text.magnifyingglass") { Task { await model.selectBinding(binding.id,owner:model.id) } }
                                .disabled(!controlsAvailable || model.store.summary.isStale)
                        }
                        .padding(10).frame(maxWidth:.infinity,alignment:.leading)
                        .background(model.store.selectedBindingID == binding.id ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.05),in:RoundedRectangle(cornerRadius:8))
                    }
                }
            }.padding(.trailing,8)
        }
    }
    @ViewBuilder private var evidenceViewer: some View {
        if model.store.selectedBindingID == nil {
            ContentUnavailableView(s(.evidenceUIChoose),systemImage:"doc.text.magnifyingglass")
        } else {
            VStack(alignment:.leading,spacing:10) {
                FindingReadNotice(state:model.store.detail)
                HStack {
                    Picker(s(.evidenceUISide),selection:$side) {
                        Text(s(.evidenceUIRequest)).tag(FindingEvidenceSide.request)
                        Text(s(.evidenceUIResponse)).tag(FindingEvidenceSide.response)
                    }.pickerStyle(.segmented)
                    Button(s(.evidenceUIDownload),systemImage:"square.and.arrow.down") { _ = model.startExport(side,owner:model.id,chooser:presenter) }.disabled(!model.canExport)
                }
                if let value = model.preview(side) {
                    if value.binary { Text(s(.evidenceUIBinary)).foregroundStyle(.secondary) }
                    Text(AppStrings.formatted(.evidenceUIBytes,language:language,values:["loaded":String(value.nextOffset),"total":String(value.total)])).font(.caption.monospacedDigit())
                    ScrollView([.horizontal,.vertical]) {
                        Text(verbatim:(side == .request ? model.requestHeader : model.responseHeader)+"\n\n"+value.content)
                            .font(.system(.body,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.topLeading).padding(10)
                    }.background(Color.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:6))
                    if value.hasMore {
                        Button(s(.evidenceUILoadMore)) { Task { await model.more(side,owner:model.id) } }.disabled(!controlsAvailable || model.store.detail.isStale)
                    }
                }
                if model.isExporting {
                    HStack { ProgressView().controlSize(.small); Text(s(.evidenceUIExporting)); Button(s(.findingUICancel)) { model.cancelExport() } }
                }
                if let file = model.saved {
                    Text(AppStrings.formatted(.evidenceUISaved,language:language,values:["name":file.url.lastPathComponent,"bytes":String(file.byteCount)])).textSelection(.enabled)
                    Text(verbatim:"SHA-256: "+file.sha256).font(.caption.monospaced()).textSelection(.enabled)
                    if !file.stagingCleanupComplete || !file.directorySynced { Text(s(.evidenceUISavedWarning)).foregroundStyle(.orange) }
                }
            }.padding(.leading,10)
        }
    }
    private func role(_ raw: String) -> String {
        let key: AppStringKey? = switch FindingTrafficRole(rawValue:raw) {
        case .baseline: .evidenceUIBaseline
        case .proof: .evidenceUIProof
        case .verification: .evidenceUIVerification
        case .supporting: .evidenceUISupporting
        case nil: nil
        }
        return key.map(s) ?? raw
    }
}
