import NetworkPNTRCore
import Darwin
import Foundation

@MainActor enum CloudActivationProbe {
    static func run(_ args: [String]) async {
        #if DEBUG
        if args.count == 2 {
            await exercise(artifacts: URL(fileURLWithPath: args[0]), output: URL(fileURLWithPath: args[1]))
            return
        }
        #endif
        FileHandle.standardError.write(Data("Usage: DEBUG VMProbe --cloud-activation ARTIFACTS NEW_PRIVATE_OUTPUT\n".utf8))
        exit(2)
    }

    #if DEBUG
    private final class Vault: SessionVault {
        func load() throws -> String? { nil }
        func save(_ token: String) throws { throw RuntimeError.integrity("unexpected session") }
        func remove() throws {}
    }

    private static func exercise(artifacts: URL, output: URL) async {
        var activeRuntime: DesktopRuntime?
        var stage = "prepare"
        do {
            guard mkdir(output.path, 0o700) == 0 else { throw RuntimeError.integrity("new private output required") }
            let rejected = output.appendingPathComponent("rejected")
            try FileManager.default.createDirectory(at: rejected, withIntermediateDirectories: false)
            let manifest = artifacts.appendingPathComponent("manifest.json")
            let manifestData = try Data(contentsOf: manifest)
            guard ArtifactIntegrity.sha256(manifestData) == GuestArtifacts.cloudEgressManifestSHA256 else {
                throw RuntimeError.integrity("probe manifest identity")
            }
            var altered = manifestData
            altered.append(0x0a)
            try altered.write(to: rejected.appendingPathComponent("manifest.json"))
            let rejectedRuntime = DesktopRuntime(artifacts: rejected, paths: .init(root: output.appendingPathComponent("rejected-state")),
                                                 vault: Vault(), cloudEgress: true)
            activeRuntime = rejectedRuntime
            stage = "reject-tampered"
            await rejectedRuntime.start()
            guard rejectedRuntime.error == RuntimeError.integrity("cloud egress manifest digest").localizedDescription,
                  rejectedRuntime.controller.state == .failed, !rejectedRuntime.controller.hasMachine,
                  rejectedRuntime.authentication == nil, !rejectedRuntime.controller.cloudEgressActive else {
                throw RuntimeError.integrity("cloud preview manifest rejection")
            }

            for cloudEgress in [false, true] {
                let mode = cloudEgress ? "enabled" : "disabled"
                stage = "start-\(mode)"
                let paths = ManagedRuntimePaths(root: output.appendingPathComponent(mode))
                let runtime = DesktopRuntime(artifacts: artifacts, paths: paths, vault: Vault(), cloudEgress: cloudEgress)
                activeRuntime = runtime
                await runtime.start()
                let controller = runtime.controller
                guard runtime.error == nil, runtime.authentication?.phase == .needsSetup,
                      controller.state == .running, controller.guestReady,
                      controller.cloudEgressActive == cloudEgress else {
                    throw RuntimeError.integrity("desktop preview activation")
                }
                if !cloudEgress {
                    do {
                        try controller.enableCloudEgress()
                    } catch RuntimeError.integrity(let reason) {
                        guard reason == "cloud egress boot authorization" else { throw RuntimeError.integrity("unexpected listener denial") }
                    }
                    guard !controller.cloudEgressActive else { throw RuntimeError.integrity("unrequested listener") }
                }
                stage = "stop-\(mode)"
                try await runtime.stop()
                let audit = GuestBootDiagnostics.audit(logDirectory: paths.logs, tokens: [CloudEgressVMFixture.key])
                guard runtime.authentication == nil, controller.state == .stopped, !controller.hasMachine,
                      !controller.cloudEgressActive, audit.complete, audit.isolationWitnessesPresent,
                      audit.diagnostics.isEmpty, audit.formatStageObserved else {
                    throw RuntimeError.integrity("desktop preview stopped audit")
                }
                print("PASS desktop_cloud_egress=\(mode) auth_ready=true stopped=true nic=0 shares=0")
            }
            print("PASS cloud_preview_tampered_manifest_rejected_before_boot=true")
        } catch {
            if let runtime = activeRuntime, runtime.controller.hasMachine { try? await runtime.forceStop() }
            FileHandle.standardError.write(Data("FAIL cloud_activation_stage=\(stage)\n".utf8))
            exit(1)
        }
    }
    #endif
}
