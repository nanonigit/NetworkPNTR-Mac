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
        let paths = diagnosticsDirectory.map { ManagedRuntimePaths(root: $0.appendingPathComponent("State", isDirectory: true)) } ?? .applicationDefault
        let account = diagnosticsDirectory == nil ? "dedicated-guest-session" : "native-diagnostics-" + UUID().uuidString
        return DesktopRuntime(artifacts: Bundle.main.resourceURL!.appendingPathComponent("Guest"), paths: paths, vault: KeychainSessionVault(account: account))
    }
}
