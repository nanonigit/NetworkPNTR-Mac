import AppKit
import NetworkPNTRCore
import SwiftUI

/// One instance per conversation identity; no callback can edit another conversation's binding.
struct ChatMentionComposer: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }

    @Binding var text: String
    let mode: String
    let disabled: Bool
    let send: () -> Void
    @State private var results: ChatMentionSearchStore
    @State private var caret: Int?
    @State private var composing = false
    @State private var dismissed = false
    @State private var activeIndex = 0
    @State private var pendingKeyboardIndex: Int?
    @State private var selection: ChatMentionSelection?
    @State private var lastEditedText: String
    @State private var shownKey: Data?
    @State private var debouncing = false
    @State private var epoch = UUID()
    @State private var retry = UUID()
    init(text: Binding<String>, service: ChatMentionService, mode: String, disabled: Bool, send: @escaping () -> Void) {
        _text = text; self.mode = mode; self.disabled = disabled; self.send = send
        _lastEditedText = State(initialValue: text.wrappedValue)
        _results = State(initialValue: ChatMentionSearchStore(service: service))
    }
    private var active: ChatMentionActive? {
        guard !disabled, !dismissed, let caret else { return nil }
        return ChatMentionEditing.active(in: text, caret: caret, composing: composing)
    }
    private var input: ChatMentionSearchInput { ChatMentionEditing.search(active?.query ?? "") }
    private var key: Data? {
        guard active != nil, input.categories.isEmpty else { return nil }
        return Data(((input.kind?.rawValue ?? "") + "\0" + input.query).utf8)
    }
    private var items: [ChatMention] { shownKey == key ? results.items : [] }
    private var loading: Bool { key != nil && (shownKey != key || debouncing || results.loading) }
    private var count: Int { input.categories.isEmpty ? items.count : input.categories.count }
    private func title(_ kind: ChatMentionKind) -> String {
        switch kind {
        case .finding: s(.findings); case .asset: s(.assets); case .company: s(.chatCompany); case .endpoint: "API"; case .ip: "IP"
        case .app: s(.chatApp); case .rootDomain: s(.chatDomain); case .subdomain: s(.chatSubdomain); case .service: s(.chatService)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if active != nil { candidates }
            editor
            selectedChips
        }
        .task(id: TaskKey(query: key, retry: retry)) { await searchCandidates() }
        .onDisappear { results.cancel() }
    }
    private var editor: some View {
        ChatComposer(text: $text, mode: mode, disabled: disabled, send: send,
                     onEditing: didEdit, onMentionKey: handleKey, selectionRequest: selection)
            .frame(height: 90)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.quaternary))
    }
    private func didEdit(_ value: String, range: NSRange, marked: Bool) {
        if Array(value.utf16) != Array(lastEditedText.utf16) {
            dismissed = false; activeIndex = 0; selection = nil; pendingKeyboardIndex = nil
        }
        lastEditedText = value; caret = range.location; composing = marked
    }
    @ViewBuilder private var selectedChips: some View {
        let tokens = ChatMentionEditing.selected(in: text)
        if !tokens.isEmpty {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(Array(tokens.enumerated()), id: \.offset) { entry in
                        selectedChip(entry.element)
                    }
                }
            }
        }
    }
    private func selectedChip(_ token: ChatSelectedMention) -> some View {
        let label = title(token.kind) + "#" + token.id + " " + token.text
        return Button {
            if let edit = ChatMentionEditing.remove(token, from: text) { apply(edit, close: true) }
        } label: {
            Label(label, systemImage: "xmark.circle").lineLimit(1)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(s(.chatRemoveMentionPrefix) + label)
    }
    private func searchCandidates() async {
        let ticket = UUID(); epoch = ticket; activeIndex = 0; pendingKeyboardIndex = nil; results.cancel(); shownKey = key
        guard key != nil else { debouncing = false; return }
        debouncing = true
        defer { if epoch == ticket { debouncing = false } }
        do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
        guard !Task.isCancelled else { return }
        let search = input
        await results.search(kind: search.kind, query: search.query)
    }
    private struct TaskKey: Hashable { let query: Data?; let retry: UUID }
    private var candidates: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(s(.chatCiteRecord)).font(.caption.bold()); Spacer(); Button(s(.close)) { dismissed = true } }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if !input.categories.isEmpty {
                            ForEach(Array(input.categories.enumerated()), id: \.offset) { index, kind in
                                candidate(index: index, label: title(kind), detail: "@" + kind.wireLabel)
                            }
                        } else if loading { HStack { ProgressView().controlSize(.small); Text(s(.chatSearchingMentions)) } }
                        else if let error = results.failure?.text(language: language) { Text(error).foregroundStyle(.red); Button(s(.chatSearchAgain)) { retry = UUID() } }
                        else {
                            ForEach(Array(items.enumerated()), id: \.element.identity) { index, item in
                                candidate(index: index, label: item.label, detail: item.kind + "#" + String(item.id) + " · " + item.description)
                            }
                            if items.isEmpty { Text(s(.chatNoMatches)).foregroundStyle(.secondary) }
                            if let error = results.pageFailure?.text(language: language) { Text(error).foregroundStyle(.red) }
                            if results.nextCursor != nil {
                                Button(results.loadingMore ? s(.chatLoading) : (results.pageError == nil ? s(.chatLoadMore) : s(.chatRetryMore))) { Task { await results.loadMore() } }.disabled(results.loadingMore)
                            }
                        }
                    }.padding(6)
                }.frame(maxHeight: 220)
                .onChange(of: activeIndex) { _, value in proxy.scrollTo(value, anchor: .bottom) }
                .onChange(of: items.count) { _, newCount in
                    if let pending = pendingKeyboardIndex, pending < newCount {
                        proxy.scrollTo(pending, anchor: .bottom); pendingKeyboardIndex = nil
                    }
                }
            }
        }.padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain).accessibilityLabel(s(.chatMentionCandidates))
    }
    private func candidate(index: Int, label: String, detail: String) -> some View {
        Button { choose(index) } label: {
            VStack(alignment: .leading, spacing: 2) { Text(label).lineLimit(2); Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                .frame(maxWidth: .infinity, alignment: .leading).padding(5)
                .background(index == activeIndex ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 4))
        }.buttonStyle(.plain).id(index).accessibilityLabel(label + " " + detail)
    }
    private func apply(_ edit: ChatMentionEdit, close: Bool) {
        text = edit.text; lastEditedText = edit.text; caret = edit.caret; selection = ChatMentionSelection(edit: edit); dismissed = close; activeIndex = 0
    }
    private func choose(_ index: Int) {
        guard let active else { return }
        let insertion: String; let close: Bool
        if input.categories.indices.contains(index) { insertion = "@" + input.categories[index].wireLabel + " "; close = false }
        else if !loading, items.indices.contains(index) { insertion = items[index].token + " "; close = true }
        else { return }
        if let edit = ChatMentionEditing.replace(in: text, active: active, with: insertion) { apply(edit, close: close) }
    }
    private func handleKey(_ event: NSEvent) -> Bool {
        guard active != nil else { return false }
        if event.keyCode == 53 { dismissed = true; return true }
        if [125,126].contains(event.keyCode) {
            if event.keyCode == 125, input.categories.isEmpty, !loading, count > 0, activeIndex >= count - 1, results.nextCursor != nil {
                pendingKeyboardIndex = count; activeIndex = count; Task { await results.loadMore() }
            } else if count > 0 { activeIndex = (activeIndex + (event.keyCode == 125 ? 1 : count - 1)) % count }
            return true
        }
        if [36,76,48].contains(event.keyCode), event.modifierFlags.intersection([.shift,.control,.command]).isEmpty {
            if event.keyCode == 48, loading || count == 0 { dismissed = true; return false }
            if !loading, count > 0 { choose(min(activeIndex, count - 1)) }
            return true
        }
        return false
    }
}
