import NetworkPNTRCore
import SwiftUI

@MainActor struct LLMLocalModelsView: View {
    @Environment(\.locale) private var locale
    @State private var runtime = OllamaCatalog()
    @State private var refresh = 0
    @State private var models: [OllamaModelList.Model] = []
    @State private var running: [OllamaModelList.Model] = []
    @State private var selectedName: String?
    @State private var isLoading = true
    @State private var failure: AppStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Ollama").font(.headline)
                    Text(localString(.llmLocalDescription, locale)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(localString(.llmUIReload, locale), systemImage: "arrow.clockwise") { refresh += 1 }
                    .disabled(isLoading)
            }
            if isLoading {
                ProgressView(localString(.llmUILoading, locale)).controlSize(.small)
            } else if let failure {
                Label(localString(failure, locale), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else if models.isEmpty {
                ContentUnavailableView(localString(.llmLocalEmpty, locale), systemImage: "internaldrive")
            } else {
                Picker(localString(.llmLocalModel, locale), selection: $selectedName) {
                    ForEach(models, id: \.name) { model in
                        Text(verbatim: model.name).tag(Optional(model.name))
                    }
                }
                .accessibilityIdentifier("llm-local-model")
                if let selected = models.first(where: { $0.name == selectedName }) {
                    ScrollView {
                        LLMLocalModelDetails(
                            runtime: runtime, model: selected,
                            running: running.first(where: { $0.name == selected.name })
                        )
                        .id(selected.name)
                    }
                }
            }
        }
        .task(id: refresh) {
            isLoading = true
            failure = nil
            do {
                try await runtime.requireLocalOnly()
                let installed = try await runtime.installed()
                let loaded = try await runtime.running()
                try Task.checkCancellation()
                models = installed.models
                running = loaded.models
                if !models.contains(where: { $0.name == selectedName }) {
                    selectedName = models.first?.name
                }
            } catch {
                guard !Task.isCancelled else { return }
                failure = localFailure(error)
            }
            isLoading = false
        }
    }
}

@MainActor private struct LLMLocalModelDetails: View {
    @Environment(\.locale) private var locale
    let runtime: OllamaCatalog
    let model: OllamaModelList.Model
    let running: OllamaModelList.Model?
    @State private var metadata: OllamaModelMetadata?
    @State private var metadataFailed = false
    @State private var test = LocalInferenceTest()
    @State private var refreshedRunning: [OllamaModelList.Model]?

    private var loadedModel: OllamaModelList.Model? {
        guard let refreshedRunning else { return running }
        return refreshedRunning.first(where: { $0.name == model.name })
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if let quantization = model.details?.quantizationLevel {
                    LabeledContent(localString(.llmLocalQuantization, locale), value: quantization)
                }
                if let maximum = metadata?.maximumContext {
                    LabeledContent(localString(.llmLocalMaximumContext, locale), value: maximum.formatted(.number.locale(locale)))
                }
                if let context = loadedModel?.contextLength {
                    LabeledContent(localString(.llmLocalLoadedContext, locale), value: context.formatted(.number.locale(locale)))
                }
                if let bytes = loadedModel?.sizeVRAM {
                    LabeledContent(localString(.llmLocalGpuMemory, locale), value: bytes.formatted(.byteCount(style: .memory).locale(locale)))
                }
                if metadataFailed {
                    Text(localString(.llmLocalMetadataUnavailable, locale)).foregroundStyle(.secondary)
                }
                Button(localString(.llmLocalTest, locale), systemImage: "waveform.path.ecg") { test.request() }
                    .disabled(test.isRunning)
                    .accessibilityIdentifier("llm-local-test")
                if test.isRunning {
                    ProgressView().controlSize(.small)
                } else if let testFailure = test.failure {
                    Label(localString(localFailure(testFailure), locale), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                } else if let metrics = test.metrics {
                    if let input = metrics.inputTokens, let output = metrics.outputTokens {
                        LabeledContent(localString(.llmLocalTokens, locale), value: "\(input) / \(output)")
                    }
                    if let speed = metrics.outputTokensPerSecond {
                        LabeledContent("tokens/s", value: speed.formatted(.number.precision(.fractionLength(1)).locale(locale)))
                    }
                    if let ns = metrics.totalNanoseconds, ns >= 0 {
                        LabeledContent(localString(.llmLocalResponseTime, locale), value: (Double(ns) / 1e9).formatted(.number.precision(.fractionLength(2)).locale(locale)))
                    }
                }
            }
            .padding(8)
        }
        .task {
            do {
                let details = try await runtime.metadata(forInstalledModel: model.name)
                try Task.checkCancellation()
                metadata = details
            } catch {
                if !Task.isCancelled { metadataFailed = true }
            }
        }
        .task(id: test.requestID) {
            let completed = await test.runPending {
                try await runtime.chat(
                    model: model.name,
                    messages: [.init(role: .user, content: "Reply with the word OK.")]
                )
            }
            guard completed, !Task.isCancelled else { return }
            let loaded = try? await runtime.running()
            guard !Task.isCancelled else { return }
            refreshedRunning = loaded?.models
        }
    }
}

private func localString(_ key: AppStringKey, _ locale: Locale) -> String {
    AppStrings.text(key, language: AppLanguage.preferred(in: [locale.identifier]))
}

private func localFailure(_ error: Error) -> AppStringKey {
    if (error as? OllamaCatalog.Failure) == .cloudEnabled { return .llmLocalCloudEnabled }
    return .llmLocalUnavailable
}
