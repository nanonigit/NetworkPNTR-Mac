import NetworkPNTRCore
import Foundation

@MainActor enum RuntimeFactory {
    static var diagnosticsDirectory: URL? {
        #if DEBUG
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--native-diagnostics"), args.indices.contains(index + 1) { return URL(fileURLWithPath: args[index + 1]) }
        #endif
        return nil
    }
    static func usesAutomaticSession(diagnostics: URL?, arguments: [String]) -> Bool {
        diagnostics == nil || arguments.contains("--local-session-diagnostics")
    }
    static func usesCloudRuntime(bundleVariant: Any?, diagnostics: URL?, arguments: [String]) throws -> Bool {
        let variant: String
        if let bundleVariant {
            guard let value = bundleVariant as? String else { throw RuntimeError.integrity("runtime variant type") }
            variant = value
        } else { variant = "default" }
        guard ["default", "cloud-preview"].contains(variant) else { throw RuntimeError.integrity("runtime variant") }
        return diagnostics == nil && (variant == "cloud-preview" || arguments.contains("--cloud-egress"))
    }
    static let cloudBundleIdentifier = "com.nanonigit.networkpntr-mac.cloud-preview"
    static func migrateCloudLanguagePreference(bundleIdentifier: String?, defaults: UserDefaults, legacy: UserDefaults?) {
        guard bundleIdentifier == cloudBundleIdentifier, defaults.object(forKey: AppLanguagePreferences.key) == nil,
              let value = legacy?.object(forKey: AppLanguagePreferences.key) as? String,
              AppLanguage(rawValue: value) != nil else { return }
        defaults.set(value, forKey: AppLanguagePreferences.key)
    }
    static func makeLanguagePreferences() -> AppLanguagePreferences {
        if Bundle.main.bundleIdentifier == cloudBundleIdentifier {
            migrateCloudLanguagePreference(bundleIdentifier: Bundle.main.bundleIdentifier, defaults: .standard,
                legacy: UserDefaults(suiteName: "com.nanonigit.artex-mac"))
        }
        return AppLanguagePreferences()
    }
    static func make() -> DesktopRuntime {
        let diagnostics = diagnosticsDirectory
        let cloudEgress: Bool
        let configurationFailure: RuntimeError?
        do {
            cloudEgress = try usesCloudRuntime(bundleVariant: Bundle.main.object(forInfoDictionaryKey: "NetworkPNTRRuntimeVariant"),
                diagnostics: diagnostics, arguments: CommandLine.arguments)
            configurationFailure = nil
        } catch {
            cloudEgress = false
            configurationFailure = .integrity("runtime variant")
        }
        let paths: ManagedRuntimePaths
        let account: String
        if let diagnostics {
            paths = ManagedRuntimePaths(root: diagnostics.appendingPathComponent("State", isDirectory: true))
            account = "native-diagnostics-" + UUID().uuidString
        } else if cloudEgress {
            paths = ManagedRuntimePaths(root: ManagedRuntimePaths.applicationDefault.root.appendingPathExtension("cloud-preview"))
            account = "cloud-preview-guest-session"
        } else {
            paths = .applicationDefault
            account = "dedicated-guest-session"
        }
        let automaticLocalSession = usesAutomaticSession(diagnostics: diagnostics, arguments: CommandLine.arguments)
        let vault: any SessionVault = automaticLocalSession ? EphemeralSessionVault() : KeychainSessionVault(account: account)
        return DesktopRuntime(artifacts: Bundle.main.resourceURL!.appendingPathComponent("Guest"),
                              paths: paths, vault: vault, cloudEgress: cloudEgress, automaticLocalSession: automaticLocalSession, configurationFailure: configurationFailure)
    }
}
