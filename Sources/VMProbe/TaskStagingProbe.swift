import NetworkPNTRCore
import Foundation

@MainActor private final class StagingProbeVault: SessionVault {
    var token: String?
    func load() throws -> String? { token }
    func save(_ token: String) throws { self.token = token }
    func remove() throws { token = nil }
}

@MainActor enum TaskStagingProbe {
    static func run(_ args: [String]) async {
        guard args.count == 2 else { print("Usage: VMProbe --task-staging ARTIFACTS NEW_PRIVATE_OUTPUT"); exit(2) }
        let controller = VMController(), output = URL(fileURLWithPath: args[1])
        var created = false, attempted = false, ready = false, freshAuth = false, cooperative = false
        var protectedStatus: Int?, tokens: [String] = []
        var stage = TaskStagingRunStage.preparing, exercise: TaskStagingExerciseReport?
        func report(terminalSuccess: Bool = false) -> TaskStagingRunReport {
            let boot = BackendPreflightReport(reachedReady: ready, freshAuth: freshAuth, protectedStatus: protectedStatus,
                cooperativeStop: cooperative, machineStopped: !controller.hasMachine,
                audit: GuestBootDiagnostics.audit(logDirectory: output, tokens: tokens), bootAttempts: attempted ? 1 : 0)
            return TaskStagingRunReport(stage: stage, boot: boot, exercise: exercise, terminalSuccess: terminalSuccess)
        }
        func write(_ result: TaskStagingRunReport) throws {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(result).write(to: output.appendingPathComponent("task-staging-vm.json"), options: .atomic)
        }
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            created = true
            let selected = output.appendingPathComponent("selected", isDirectory: true)
            try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try FileManager.default.createDirectory(at: selected.appendingPathComponent("second"), withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let files = [selected.appendingPathComponent("fixture.bin"), selected.appendingPathComponent("empty.txt"), selected.appendingPathComponent("second/fixture.bin"), selected.appendingPathComponent(TaskStagingExercise.inputNames[3])]
            for (file, bytes) in zip(files,TaskStagingExercise.contents) { try bytes.write(to: file, options: .withoutOverwriting) }
            let disk = output.appendingPathComponent("state-" + UUID().uuidString + ".ext4")
            _ = try PersistentGuestDisk.createIfMissing(at: disk, byteCount: 2 * 1024 * 1024 * 1024)
            let provisioning = try GuestProvisioning.generate()
            tokens = [provisioning.transportToken, provisioning.setupToken]
            let password = UUID().uuidString + "-fixture"; tokens.append(password)
            stage = .boot; attempted = true
            try await controller.start(artifacts: URL(fileURLWithPath: args[0]), logs: output, readinessTimeout: .seconds(120), dataDisk: disk, provisioning: provisioning)
            for _ in 0..<1300 {
                if controller.guestReady || controller.state == .failed || controller.state == .stopped { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            let witnesses = ["network_hardware_devices=0", "network_nonloopback_up=0", "network_external_routes=0", "shared_mounts=0"]
            let lines = Set(controller.guestLog.components(separatedBy: .newlines))
            guard controller.guestReady, witnesses.allSatisfy(lines.contains) else { throw RuntimeError.integrity("staging boot") }
            ready = true; stage = .authentication
            let raw = BackendJSONClient(runtime: controller, provisioning: provisioning)
            let denied = try await raw.send(method: "GET", path: "/api/llm/profiles", body: nil, bearer: nil)
            protectedStatus = denied.status
            guard denied.status == 401 else { throw RuntimeError.integrity("staging protected API") }
            let vault = StagingProbeVault(), session = AuthenticationSession(client: raw, vault: vault, setupToken: provisioning.setupToken)
            await session.refresh()
            guard session.phase == .needsSetup else { throw RuntimeError.integrity("staging fresh auth") }
            freshAuth = true
            await session.setup(password: password, confirmation: password)
            guard session.phase == .authenticated, let token = vault.token else { throw RuntimeError.integrity("staging setup") }
            tokens.append(token)
            let client = AuthenticatedBackendClient(session: session)
            stage = .transfer
            exercise = try await TaskStagingExercise.run(files: files, draftID: UUID(), client: client, uploader: client)
            session.logout()
            guard session.phase == .needsLogin, vault.token == nil else { throw RuntimeError.integrity("staging logout") }
            stage = .shutdown
            try await controller.stop(); cooperative = true
            stage = .complete
            let stopped = report(terminalSuccess: true)
            guard stopped.passed else { throw RuntimeError.integrity("staging complete log audit") }
            try write(stopped)
            print("PASS task_staging_single_boot=true actual_vsock_upload=true byte_readback=true originals_preserved=true cooperative_stop=true")
        } catch {
            try? await controller.forceStop()
            if created { try? write(report()) }
            FileHandle.standardError.write(Data("FAIL task_staging_stage=\(stage.rawValue) boot_attempted=\(attempted) machine_stopped=\(!controller.hasMachine)\n".utf8))
            exit(1)
        }
    }
}
