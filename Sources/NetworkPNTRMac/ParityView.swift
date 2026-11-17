import NetworkPNTRCore
import SwiftUI
struct ParityView: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    private func f(_ key: AppStringKey, _ values: [String: String]) -> String { AppStrings.formatted(key, language: language, values: values) }
    let catalog: FeatureCatalog
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(s(.runtimeUIParityTitle)).font(.largeTitle.bold())
            Text(f(.runtimeUIParityBaseline, ["commit": String(catalog.baseline.prefix(12)), "features": String(catalog.features.count), "routes": String(catalog.routes.count), "endpoints": String(catalog.endpoints.count)])).foregroundStyle(.secondary)
            Text(s(.runtimeUIParityHelp))
            Table(catalog.features) {
                TableColumn(s(.runtimeUIParityFeature)) { feature in Text(AppStrings.featureTitle(feature.id, fallback: feature.title, language: language)) }
                TableColumn(s(.runtimeUIParityBrowser), value: \.browserPath)
                TableColumn(s(.runtimeUIParityStatus)) { feature in Text(feature.nativeStatus == "in_progress" ? s(.runtimeUIParityInProgress) : f(.runtimeUIParityWaiting, ["phase": String(feature.phase)])) }
            }
        }.padding(28).navigationTitle(s(.parity))
    }
}
