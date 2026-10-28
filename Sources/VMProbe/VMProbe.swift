import ArtexCore
import Foundation

@main struct VMProbe {
    @MainActor static func main() async {
        let args = CommandLine.arguments
        guard args.count >= 3 else { FileHandle.standardError.write(Data("Usage: VMProbe guest-artifacts log-directory\n".utf8)); exit(2) }
        if args[1] == "--findings" { await FindingProbe.run(Array(args.dropFirst(2))); return }
        if args[1] == "--evidence-export" { await EvidenceExportProbe.run(Array(args.dropFirst(2))); return }
        if args[1] == "--task-archive" { await TaskArchiveProbe.run(Array(args.dropFirst(2))); return }
        if args[1] == "--task-catalog" { await TaskCatalogProbe.run(Array(args.dropFirst(2))); return }
        if args[1] == "--task-staging" { await TaskStagingProbe.run(Array(args.dropFirst(2))); return }
        if args[1] == "--backend-preflight" { await BackendProbe.run(Array(args.dropFirst(2)), preflightOnly: true); return }
        if args[1] == "--backend" { await BackendProbe.run(Array(args.dropFirst(2))); return }
        let controller = VMController()
        do {
            let badDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.copyItem(at: URL(fileURLWithPath: args[1]), to: badDirectory)
            defer { try? FileManager.default.removeItem(at: badDirectory) }
            try Data("corrupt".utf8).write(to: badDirectory.appendingPathComponent("Image"))
            do {
                try await controller.start(artifacts: badDirectory, logs: URL(fileURLWithPath: args[2]))
                throw RuntimeError.integrity("tampered image was accepted")
            } catch RuntimeError.integrity {
                guard controller.state == .failed, !controller.hasMachine else { throw RuntimeError.integrity("tampering must fail before VM creation") }
                print("PASS tampered_image_rejected_before_vm_creation=true")
            }
            for cycle in 1...2 {
                try await controller.start(artifacts: URL(fileURLWithPath: args[1]), logs: URL(fileURLWithPath: args[2]))
                for _ in 0..<600 {
                    if controller.guestReady || controller.state == .failed || controller.state == .stopped { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard controller.guestReady else { throw RuntimeError.timeout("probe guest readiness: " + controller.guestLog) }
                guard controller.guestLog.contains("network_interfaces=lo"), controller.guestLog.contains("shared_mounts=0"), controller.guestLog.contains("guest_arch=aarch64") else { throw RuntimeError.integrity("guest isolation evidence") }
                try await controller.stop()
                guard controller.state == .stopped else { throw RuntimeError.timeout("probe shutdown") }
                print("PASS cycle=\(cycle) real_linux_boot=true docker_used=false shares=0 network_devices=0 cooperative_stop=true")
            }
            if args.count > 3 {
                try await controller.start(artifacts: URL(fileURLWithPath: args[3]), logs: URL(fileURLWithPath: args[2]), readinessTimeout: .seconds(2))
                for _ in 0..<100 {
                    if controller.state == .failed { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard controller.state == .failed, !controller.guestReady, controller.hasMachine, controller.lastError?.contains("Timed out") == true else { throw RuntimeError.integrity("guest readiness timeout must be visible") }
                try await controller.forceStop()
                guard controller.state == .stopped, !controller.hasMachine else { throw RuntimeError.integrity("force-stop recovery") }
                print("PASS actual_guest_readiness_timeout_visible=true force_stop_recovery=true")
            }
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error.localizedDescription)\n".utf8))
            try? await controller.forceStop()
            exit(1)
        }
    }
}
