import ArtexCore
import Foundation

@MainActor enum RuntimeFactory {
    static var diagnosticsDirectory: URL? {
        #if DEBUG
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--native-diagnostics"), args.indices.contains(index + 1) { return URL(fileURLWithPath: args[index + 1]) }
        #endif
        return nil
    }
    static func make() -> DesktopRuntime {
        let diagnostics = diagnosticsDirectory
        let cloudEgress = diagnostics == nil && CommandLine.arguments.contains("--cloud-egress")
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
        return DesktopRuntime(artifacts: Bundle.main.resourceURL!.appendingPathComponent("Guest"),
                              paths: paths, vault: KeychainSessionVault(account: account), cloudEgress: cloudEgress)
    }
}
