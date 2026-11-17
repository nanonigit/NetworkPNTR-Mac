import NetworkPNTRCore
import Darwin
import Foundation

@MainActor enum FindingProbe {
    static func run(_ args: [String]) async {
        guard args.count == 2 else {
            FileHandle.standardError.write(Data("Usage: VMProbe --findings ARTIFACTS NEW_PRIVATE_OUTPUT\n".utf8)); exit(2)
        }
        #if DEBUG
        await runDebug(args)
        #else
        FileHandle.standardError.write(Data("Findings fixture probe requires a developer build\n".utf8)); exit(2)
        #endif
    }
    #if DEBUG
    @MainActor private final class Vault: SessionVault {
        var token: String?
        func load() throws -> String? { token }
        func save(_ token: String) throws { self.token = token }
        func remove() throws { token = nil }
    }
    private struct Provenance: Codable {
        let sourceCommit: String
        let backendSHA256: String
        let backendImage: String
    }
    private struct Inputs: Encodable {
        let provenance: Provenance
        let artifacts: GuestArtifacts
        let seedSHA256: String
        let controlSHA256: String
    }
    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(value).write(to:url,options:.atomic)
    }
    private static func progress(_ value: String) {
        FileHandle.standardOutput.write(Data((value + "\n").utf8))
    }
    private static func runDebug(_ args: [String]) async {
        let output = URL(fileURLWithPath:args[1]), artifactsURL = URL(fileURLWithPath:args[0])
        let controller = VMController(), vault = Vault()
        var created = false, attempts = 0, expectedCPU = 0, seeded = false
        var stage = TaskArchiveProbeStage.preparing, boots: [TaskArchiveBootReport] = []
        var exercise: FindingExerciseReport?, checkpoint: FindingExerciseCheckpoint?
        var tokens: [String] = [], ready = false, authentication: TaskArchiveAuthenticationProof?, protectedStatus: Int?, cooperative = false
        var logDirectory: URL?
        func appendBoot() {
            guard attempts > 0, boots.last?.index != attempts, let logs = logDirectory else { return }
            boots.append(TaskArchiveBootReport(index:attempts,reachedReady:ready,authentication:authentication,
                protectedStatus:protectedStatus,cpuCount:controller.configuredCPUCount,cooperativeStop:cooperative,
                machineStopped:!controller.hasMachine,audit:GuestBootDiagnostics.audit(logDirectory:logs,tokens:tokens)))
        }
        func report(_ success: Bool = false) -> FindingRunReport {
            .init(stage:stage,bootAttempts:attempts,expectedCPUCount:expectedCPU,boots:boots,seedConfirmed:seeded,
                  exercise:exercise,terminalSuccess:success,machineStopped:!controller.hasMachine)
        }
        do {
            // mkdir, unlike createDirectory, refuses an existing directory atomically.
            guard output.path.withCString({Darwin.mkdir($0,0o700)}) == 0 else { throw RuntimeError.integrity("findings private output") }
            created = true
            let artifacts = try GuestArtifacts.load(from:artifactsURL)
            expectedCPU = artifacts.cpuCount ?? 2
            let provenance = try JSONDecoder().decode(Provenance.self,from:Data(contentsOf:artifactsURL.appendingPathComponent("manifest.json")))
            guard provenance.sourceCommit == "e75ae371ad777ffd1eecdd28d2781a6519b05591",
                  provenance.backendSHA256.utf8.count == 64, provenance.backendImage.hasPrefix("sha256:") else { throw RuntimeError.integrity("findings source inputs") }
            let disk = output.appendingPathComponent("state.ext4")
            _ = try PersistentGuestDisk.createIfMissing(at:disk,byteCount:2 * 1024 * 1024 * 1024)
            let password = UUID().uuidString + "-fixture"; tokens.append(password)
            var sourceHashes: [String]?
            for index in 1...3 {
                let provisioning = try GuestProvisioning.generate()
                tokens.append(contentsOf:[provisioning.transportToken,provisioning.setupToken])
                ready = false; authentication = nil; protectedStatus = nil; cooperative = false
                logDirectory = output.appendingPathComponent("boot-\(index)")
                stage = .boot; attempts = index; progress("findings_boot=\(index) stage=boot")
                try await controller.start(artifacts:artifactsURL,logs:logDirectory!,readinessTimeout:.seconds(120),dataDisk:disk,provisioning:provisioning)
                for _ in 0..<1300 {
                    if controller.guestReady || controller.state == .failed || controller.state == .stopped { break }
                    try await Task.sleep(for:.milliseconds(100))
                }
                let witnesses = ["network_hardware_devices=0","network_nonloopback_up=0","network_external_routes=0","shared_mounts=0"]
                let lines = Set(controller.guestLog.components(separatedBy:.newlines))
                guard controller.guestReady, witnesses.allSatisfy(lines.contains) else { throw RuntimeError.integrity("findings guest readiness") }
                ready = true; stage = .authentication; progress("findings_boot=\(index) stage=authentication")
                let raw = BackendJSONClient(runtime:controller,provisioning:provisioning)
                protectedStatus = try await raw.send(method:"GET",path:"/api/llm/profiles",body:nil,bearer:nil).status
                guard protectedStatus == 401 else { throw RuntimeError.integrity("findings protected API") }
                let session = AuthenticationSession(client:raw,vault:vault,setupToken:provisioning.setupToken)
                await session.refresh()
                if index == 1 {
                    guard session.phase == .needsSetup else { throw RuntimeError.integrity("findings fresh authentication") }
                    await session.setup(password:password,confirmation:password)
                }
                guard session.phase == .authenticated, let token = vault.token else { throw RuntimeError.integrity("findings persisted authentication") }
                authentication = index == 1 ? .freshSetup : .persistedSession
                tokens.append(token)
                let client = AuthenticatedBackendClient(session:session)
                let fixture = try FindingFixtureClient(client:client,progress:{progress("findings_boot=\(index) operation="+$0)})
                let hashes = [fixture.seedSHA256,fixture.controlSHA256]
                if let previous = sourceHashes {
                    guard previous == hashes else { throw RuntimeError.integrity("findings source changed during experiment") }
                } else {
                    sourceHashes = hashes
                    try write(Inputs(provenance:provenance,artifacts:artifacts,seedSHA256:hashes[0],controlSHA256:hashes[1]),to:output.appendingPathComponent("source-inputs.json"))
                }
                if index == 1 {
                    stage = .seed; progress("findings_boot=1 stage=seed")
                    try await fixture.seed(); seeded = true
                } else {
                    let runner = FindingExercise(client:client,fixture:fixture,progress:{progress("findings_boot=\(index) operation=" + $0)})
                    if index == 2 {
                        stage = .beforeRestart
                        checkpoint = try await runner.runBeforeRestart()
                        try write(checkpoint!,to:output.appendingPathComponent("checkpoint.json"))
                    } else {
                        stage = .afterRestart
                        guard let checkpoint else { throw RuntimeError.integrity("findings checkpoint missing") }
                        exercise = try await runner.runAfterRestart(checkpoint)
                        guard exercise?.passed == true else { throw RuntimeError.integrity("findings exercise incomplete") }
                    }
                }
                stage = .shutdown; progress("findings_boot=\(index) stage=shutdown")
                try await controller.stop()
                guard !controller.hasMachine, controller.lastStopInterruptedTransferCount == 0 else { throw RuntimeError.integrity("findings cooperative stop") }
                cooperative = true; appendBoot()
                guard boots.last?.passed == true else { throw RuntimeError.integrity("findings complete boot audit") }
                try write(report(),to:output.appendingPathComponent("findings-vm.json"))
            }
            stage = .complete
            let final = report(true)
            guard final.passed else { throw RuntimeError.integrity("findings complete experiment") }
            try write(final,to:output.appendingPathComponent("findings-vm.json"))
            progress("PASS findings_three_boots=true initial_and_persisted_reads=true partial_patch_http500=true explicit_ack=true cooperative_stops=true")
        } catch {
            try? await controller.forceStop(); appendBoot()
            if created { try? write(report(),to:output.appendingPathComponent("findings-vm.json")) }
            FileHandle.standardError.write(Data("FAIL findings_stage=\(stage.rawValue) boot_attempts=\(attempts) machine_stopped=\(!controller.hasMachine)\n".utf8))
            exit(1)
        }
    }
    #endif
}

/// The shared three-boot log proof also used by task archives has no archive side effects.
struct FindingRunReport: Encodable {
    let stage: TaskArchiveProbeStage
    let bootAttempts: Int
    let expectedCPUCount: Int
    let boots: [TaskArchiveBootReport]
    let seedConfirmed: Bool
    let exercise: FindingExerciseReport?
    let terminalSuccess: Bool
    let machineStopped: Bool
    let passed: Bool
    @MainActor init(stage: TaskArchiveProbeStage,bootAttempts: Int,expectedCPUCount: Int,boots: [TaskArchiveBootReport],
                    seedConfirmed: Bool,exercise: FindingExerciseReport?,terminalSuccess: Bool,machineStopped: Bool) {
        self.stage = stage; self.bootAttempts = bootAttempts; self.expectedCPUCount = expectedCPUCount; self.boots = boots
        self.seedConfirmed = seedConfirmed; self.exercise = exercise; self.terminalSuccess = terminalSuccess; self.machineStopped = machineStopped
        passed = stage == .complete && bootAttempts == 3 && expectedCPUCount > 0 && boots.map(\.index) == [1,2,3]
            && boots.allSatisfy{$0.passed && $0.cpuCount == expectedCPUCount} && seedConfirmed && terminalSuccess && machineStopped
            && exercise?.passed == true && exercise?.checkpoint.beforeRequestCount == 123 && exercise?.afterRequestCount == 100
            && exercise?.checkpoint.mutation.partialHTTPStatus == 500
    }
}
