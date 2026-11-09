import ArtexCore
import SwiftUI

@MainActor struct AssetDSLSearchField: View {
    @Environment(\.locale) private var locale
    @Binding var text: String
    @FocusState private var focused: Bool
    @State private var selection: TextSelection?
    @State private var highlighted = 0
    @State private var dismissed = false

    var body: some View {
        let suggestions = candidates
        VStack(alignment: .leading, spacing: 4) {
            TextField(s(.assetCatalogSearch), text: $text, selection: $selection)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onChange(of: focused) { _, active in
                    if active { resetSuggestions() }
                }
                .onChange(of: text) { _, _ in resetSuggestions() }
                .onChange(of: selection) { _, _ in resetSuggestions() }
                .onKeyPress(keys: [.upArrow, .downArrow, .return, .tab, .escape]) { press in
                    handle(press.key)
                }

            if !suggestions.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                                Button {
                                    insert(suggestion)
                                } label: {
                                    HStack(spacing: 10) {
                                        Text(verbatim: suggestion.label).monospaced().fontWeight(.semibold)
                                        Text(s(suggestion.descriptionKey)).foregroundStyle(.secondary)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(highlighted == index ? Color.accentColor.opacity(0.16) : .clear)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .id(index)
                            }
                        }
                    }
                    .frame(height: min(CGFloat(suggestions.count) * 27, 162))
                    .onChange(of: highlighted) { _, index in proxy.scrollTo(index) }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary) }
            }
        }
    }

    private var candidates: [AssetDSLSuggestions.Suggestion] {
        guard focused, !dismissed else { return [] }
        let caret: String.Index
        if let selection, case .selection(let range) = selection.indices,
           let position = range.lowerBound.samePosition(in: text) {
            caret = position
        } else {
            caret = text.endIndex
        }
        return AssetDSLSuggestions.items(in: text, at: caret)
    }

    private func handle(_ key: KeyEquivalent) -> KeyPress.Result {
        let suggestions = candidates
        guard !suggestions.isEmpty else { return .ignored }
        switch key {
        case .upArrow: highlighted = max(0, highlighted - 1)
        case .downArrow: highlighted = min(suggestions.count - 1, highlighted + 1)
        case .return, .tab: insert(suggestions[min(highlighted, suggestions.count - 1)])
        case .escape: dismissed = true
        default: return .ignored
        }
        return .handled
    }

    private func insert(_ suggestion: AssetDSLSuggestions.Suggestion) {
        let updated = AssetDSLSuggestions.apply(suggestion, to: text)
        text = updated.text
        selection = TextSelection(insertionPoint: updated.caret)
        focused = true
        resetSuggestions()
    }

    private func resetSuggestions() {
        dismissed = false
        highlighted = 0
    }

    private func s(_ key: AppStringKey) -> String {
        AppStrings.text(key, language: .preferred(in: [locale.identifier]))
    }
}
