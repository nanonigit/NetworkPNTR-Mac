import ArtexCore
import SwiftUI

@MainActor struct AgentPromptInspectionView: View {
    enum Inspection: Identifiable {
        case preview(String)
        case comparison(AgentPromptDetails.Version, AgentPromptDetails.Version)

        var id: String {
            switch self {
            case .preview: "preview"
            case let .comparison(older, current): "\(older.id)-\(current.id)"
            }
        }
    }

    let inspection: Inspection
    let editor: AgentPromptEditor

    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var preview: AgentPromptPreview?
    @State private var failure: AppErrorMessage?
    @State private var lines: [AgentPromptDiff.Line]?
    @State private var comparisonFinished = false

    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title).font(.title2.bold())
                Spacer()
                Button(s(.close)) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            switch inspection {
            case let .preview(draft):
                Text(s(draft.isEmpty ? .agentInspectEmptyDraft : .agentInspectSample))
                    .foregroundStyle(.secondary)
                if let preview {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if let diagnostic = preview.error, !diagnostic.isEmpty {
                                Label(s(.agentInspectRenderError), systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.red)
                                literal(diagnostic)
                            } else {
                                literal(preview.rendered)
                            }
                        }
                    }
                    .accessibilityIdentifier("agent-prompt-preview-result")
                } else if let failure {
                    Text(failure.text(language: language)).foregroundStyle(.red)
                } else {
                    ProgressView()
                }
            case let .comparison(older, current):
                comparison(older: older, current: current)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 520, idealWidth: 630, minHeight: 300, idealHeight: 460)
        .task(id: inspection.id) { await inspect() }
    }

    @ViewBuilder private func comparison(older: AgentPromptDetails.Version,
                                         current: AgentPromptDetails.Version) -> some View {
        if let lines {
            HStack {
                Label(s(.agentInspectRemoved), systemImage: "minus").foregroundStyle(.red)
                Label(s(.agentInspectAdded), systemImage: "plus").foregroundStyle(.green)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines.indices, id: \.self) { index in
                        let line = lines[index]
                        switch line.kind {
                        case .unchanged: diffLine("  ", line.text, color: .secondary)
                        case .removed: diffLine("− ", line.text, color: .red)
                        case .added: diffLine("+ ", line.text, color: .green)
                        }
                    }
                }
            }
            .accessibilityIdentifier("agent-prompt-diff-lines")
        } else if comparisonFinished {
            Text(s(.agentInspectLargeDiff)).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: "v\(older.version)").font(.headline)
                    literal(older.templateText)
                    Text(verbatim: "v\(current.version)").font(.headline)
                    literal(current.templateText)
                }
            }
        } else {
            ProgressView()
        }
    }

    private func diffLine(_ prefix: String, _ value: String, color: Color) -> some View {
        Text(verbatim: prefix + value)
            .font(.callout.monospaced())
            .foregroundStyle(color)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
    }

    private func literal(_ value: String) -> some View {
        Text(verbatim: value.isEmpty ? s(.agentDetailsEmpty) : value)
            .font(.callout.monospaced())
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var title: String {
        switch inspection {
        case .preview: s(.agentInspectPreview)
        case let .comparison(older, current):
            AppStrings.formatted(.agentInspectDiffTitle, language: language,
                                 values: ["from": String(older.version), "to": String(current.version)])
        }
    }

    private func inspect() async {
        switch inspection {
        case let .preview(template):
            do {
                let result = try await editor.preview(template: template)
                guard !Task.isCancelled else { return }
                preview = result
            } catch {
                guard !Task.isCancelled else { return }
                failure = AppErrorMessage(error)
            }
        case let .comparison(older, current):
            lines = AgentPromptDiff.compare(older: older.templateText, current: current.templateText)
            comparisonFinished = true
        }
    }

    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
}
