import ArtexCore
import Darwin
import Foundation

@MainActor enum EvidenceExportProbe {
    static func run(_ args: [String]) async {
        guard args.count == 2 else { usage(); exit(2) }
        #if DEBUG
        await runDebug(args)
        #else
        usage(); exit(2)
        #endif
    }
    private static func usage() {
        FileHandle.standardError.write(Data("Usage: developer VMProbe --evidence-export ARTIFACTS NEW_PRIVATE_OUTPUT\n".utf8))
    }
    #if DEBUG
    private final class Vault: SessionVault {
        var token: String?
        func load() throws -> String? { token }
        func save(_ token: String) throws { self.token = token }
        func remove() throws { token = nil }
    }
    private struct Provenance: Codable {
        let sourceCommit, backendSHA256, backendImage: String
    }
    private struct Boot: Codable {
        let index, cpuCount: Int
        let ready, credentialsAbsent, isolationWitnesses, formatObserved, cooperativeStop: Bool
        let diagnostics: [String]
        let files: [EvidenceFileProof]
    }
    private struct Report: Codable {
        var stage = "prepare"
        var bootAttempts = 0
        var sourceSHA256: [String: String] = [:]
        var boots: [Boot] = []
        var logoutReceiptRejected = false
        var stopReceiptRejected = false
        var restartReceiptRejected = false
        var noClobber = false
        var machineStopped = false
        var cleanupComplete = false
        var nativeProbePassed = false
        let browserComparison = false
        let nativeUIAcceptance = false
        let witnessedInFlightCancellation = false
    }
    private static func progress(_ text: String) { FileHandle.standardOutput.write(Data((text + "\n").utf8)) }
    private static func failure() -> RuntimeError { .integrity("evidence VM probe") }
    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
    private static func reject(_ receipt: EvidenceExportReceipt) throws {
        do { _ = try receipt.commit() }
        catch is CancellationError { return }
        throw failure()
    }
    private static func binding(_ id: String, from traffic: FindingTraffic) throws -> FindingTrafficBinding {
        guard let value = traffic.bindings.first(where: { $0.id == id }) else { throw failure() }
        return value
    }
    private static func stage(session: AuthenticationSession, binding: FindingTrafficBinding, side: FindingEvidenceSide, url: URL) async throws -> EvidenceExportReceipt {
        let manifest = try FindingEvidenceDownload(binding: binding, side: side)
        return try await session.authenticatedEvidenceExport(manifest, destination: EvidenceExportDestination(newFileURL: url))
    }
    private static func exportAll(session: AuthenticationSession, traffic: FindingTraffic, directory: URL) async throws -> [EvidenceFileProof] {
        guard traffic.findingId == "9101", traffic.version == 1,
              traffic.bindings.map(\.id) == ["17001", "17002"] else { throw failure() }
        var files: [EvidenceFileProof] = []
        for (id, requestName, responseName) in [("17001", "literal", "binary"), ("17002", "empty", "large")] {
            let value = try binding(id, from: traffic)
            for (side, name) in [(FindingEvidenceSide.request, requestName), (.response, responseName)] {
                guard let expected = EvidenceFixtureClient.expectedBodies[name] else { throw failure() }
                let manifest = try FindingEvidenceDownload(binding: value, side: side)
                guard manifest.expectedSize == expected.size, manifest.expectedSHA256 == expected.sha256 else { throw failure() }
                let url = directory.appendingPathComponent(id + "-" + side.rawValue + ".bin")
                let receipt = try await stage(session: session, binding: value, side: side, url: url)
                guard !FileManager.default.fileExists(atPath: url.path) else { try receipt.discard(); throw failure() }
                let saved = try receipt.commit()
                guard saved.stagingCleanupComplete, saved.directorySynced, saved.byteCount == expected.size, saved.sha256 == expected.sha256,
                      try FileManager.default.attributesOfItem(atPath: saved.url.path)[.posixPermissions] as? Int == 0o600 else { throw failure() }
                do { _ = try receipt.commit(); throw failure() } catch EvidenceExportError.integrity { }
                try receipt.discard()
                files.append(try EvidenceProbeFile.verify(saved.url, body: name, expected: expected))
                progress("evidence_saved=" + name + " bytes=" + String(expected.size))
            }
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        guard names == ["17001-request.bin", "17001-response.bin", "17002-request.bin", "17002-response.bin"] else { throw failure() }
        return files
    }
    private static func runDebug(_ args: [String]) async {
        let artifacts = URL(fileURLWithPath: args[0]), output = URL(fileURLWithPath: args[1])
        let controller = VMController(), vault = Vault()
        var report = Report(), created = false, tokens: [String] = []
        var restartReceipt: EvidenceExportReceipt?
        var restartSession: AuthenticationSession?
        var currentLogs: URL?, currentFiles: [EvidenceFileProof] = [], currentReady = false
        var currentCooperative = false
        func appendBoot() {
            guard report.bootAttempts > 0, report.boots.last?.index != report.bootAttempts, let logs = currentLogs else { return }
            let audit = GuestBootDiagnostics.audit(logDirectory: logs, tokens: tokens)
            report.boots.append(Boot(index: report.bootAttempts, cpuCount: controller.configuredCPUCount, ready: currentReady,
                credentialsAbsent: audit.credentialsAbsent, isolationWitnesses: audit.isolationWitnessesPresent,
                formatObserved: audit.formatStageObserved, cooperativeStop: currentCooperative,
                diagnostics: audit.diagnostics.map(\.rawValue), files: currentFiles))
        }
        do {
            guard mkdir(output.path, 0o700) == 0 else { throw failure() }
            created = true
            let specification = try GuestArtifacts.load(from: artifacts)
            let provenance = try JSONDecoder().decode(Provenance.self, from: Data(contentsOf: artifacts.appendingPathComponent("manifest.json")))
            guard provenance.sourceCommit == "e75ae371ad777ffd1eecdd28d2781a6519b05591",
                  provenance.backendSHA256.count == 64, provenance.backendImage.hasPrefix("sha256:") else { throw failure() }
            try write(provenance, to: output.appendingPathComponent("provenance.json"))
            let disk = output.appendingPathComponent("state.ext4")
            _ = try PersistentGuestDisk.createIfMissing(at: disk, byteCount: 2 * 1024 * 1024 * 1024)
            let password = UUID().uuidString + "-fixture"; tokens.append(password)
            for index in 1...2 {
                report.bootAttempts = index; report.stage = "boot"
                currentFiles = []; currentReady = false; currentCooperative = false
                let provisioning = try GuestProvisioning.generate()
                tokens.append(contentsOf: [provisioning.transportToken, provisioning.setupToken])
                let logs = output.appendingPathComponent("boot-" + String(index)); currentLogs = logs
                progress("evidence_boot=" + String(index) + " stage=boot")
                try await controller.start(artifacts: artifacts, logs: logs, readinessTimeout: .seconds(120), dataDisk: disk, provisioning: provisioning)
                for _ in 0..<1300 {
                    if controller.guestReady || controller.state == .failed || controller.state == .stopped { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard controller.guestReady, controller.state == .running, controller.configuredCPUCount == specification.cpuCount ?? 2 else { throw failure() }
                let witnesses = ["network_hardware_devices=0", "network_nonloopback_up=0", "network_external_routes=0", "shared_mounts=0"]
                let lines = Set(controller.guestLog.components(separatedBy: .newlines))
                guard witnesses.allSatisfy(lines.contains) else { throw failure() }
                currentReady = true; report.stage = "authentication"
                let raw = BackendJSONClient(runtime: controller, provisioning: provisioning)
                guard try await raw.send(method: "GET", path: "/api/llm/profiles", body: nil, bearer: nil).status == 401 else { throw failure() }
                let session = AuthenticationSession(client: raw, vault: vault, setupToken: provisioning.setupToken)
                await session.refresh()
                if index == 1 {
                    guard session.phase == .needsSetup else { throw failure() }
                    await session.setup(password: password, confirmation: password)
                }
                guard session.phase == .authenticated, let token = vault.token else { throw failure() }
                tokens.append(token)
                let fixture = try EvidenceFixtureClient(client: AuthenticatedBackendClient(session: session))
                if index == 1 { report.sourceSHA256 = fixture.sourceSHA256 }
                guard report.sourceSHA256 == fixture.sourceSHA256 else { throw failure() }
                report.stage = index == 1 ? "fixture" : "persisted-audit"
                progress("evidence_boot=" + String(index) + " stage=" + report.stage)
                if index == 1 { _ = try await fixture.prepare() } else { _ = try await fixture.audit() }
                if index == 2 {
                    guard let receipt = restartReceipt, restartSession?.phase == .authenticated, !Task.isCancelled else { throw failure() }
                    try reject(receipt); restartReceipt = nil; restartSession = nil; report.restartReceiptRejected = true
                }
                report.stage = "export"
                let trafficService = FindingTrafficService(client: AuthenticatedBackendClient(session: session))
                let traffic = try await trafficService.list(findingID: "9101")
                let downloads = output.appendingPathComponent("downloads-" + String(index))
                try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                currentFiles = try await exportAll(session: session, traffic: traffic, directory: downloads)
                for value in traffic.bindings {
                    for side in [FindingEvidenceSide.request, .response] {
                        let preview = try await trafficService.body(findingID: "9101", bindingID: value.id, side: side, offset: 0)
                        let expected = try FindingEvidenceDownload(binding: value, side: side)
                        guard preview.total == expected.expectedSize, preview.offset == 0, preview.nextOffset <= preview.total else { throw failure() }
                    }
                }
                if index == 1 {
                    report.stage = "ownership"
                    let existing = downloads.appendingPathComponent("17001-request.bin")
                    do { _ = try EvidenceExportDestination(newFileURL: existing); throw failure() }
                    catch EvidenceExportError.destinationExists { report.noClobber = true }
                    let first = try binding("17001", from: traffic)
                    let loggedOut = try await stage(session: session, binding: first, side: .request, url: output.appendingPathComponent("late-logout.bin"))
                    session.logout(); try reject(loggedOut); report.logoutReceiptRejected = true
                    await session.login(password: password, agreed: true)
                    guard session.phase == .authenticated, let freshToken = vault.token else { throw failure() }
                    tokens.append(freshToken)
                    let stopped = try await stage(session: session, binding: first, side: .request, url: output.appendingPathComponent("late-stop.bin"))
                    restartReceipt = try await stage(session: session, binding: first, side: .request, url: output.appendingPathComponent("late-restart.bin"))
                    restartSession = session
                    report.stage = "shutdown"; try await controller.stop()
                    guard session.phase == .authenticated, !Task.isCancelled else { throw failure() }
                    try reject(stopped); report.stopReceiptRejected = true
                } else {
                    guard currentFiles == report.boots.first?.files else { throw failure() }
                    _ = try await fixture.audit()
                    report.stage = "shutdown"; try await controller.stop()
                }
                guard !controller.hasMachine, controller.lastStopInterruptedTransferCount == 0 else { throw failure() }
                currentCooperative = true; appendBoot()
                guard let boot = report.boots.last, boot.credentialsAbsent, boot.isolationWitnesses, boot.diagnostics.isEmpty,
                      boot.ready, boot.files.count == 4, boot.formatObserved == (index == 1) else { throw failure() }
                try write(report, to: output.appendingPathComponent("evidence-native.json"))
            }
            for name in ["late-logout.bin", "late-stop.bin", "late-restart.bin"] {
                guard !FileManager.default.fileExists(atPath: output.appendingPathComponent(name).path) else { throw failure() }
            }
            guard !(try FileManager.default.contentsOfDirectory(atPath: output.path)).contains(where: { $0.hasPrefix(".artex-evidence-") }) else { throw failure() }
            report.stage = "complete"; report.machineStopped = !controller.hasMachine; report.cleanupComplete = true
            report.nativeProbePassed = report.boots.count == 2 && report.logoutReceiptRejected && report.stopReceiptRejected && report.restartReceiptRejected && report.noClobber && report.machineStopped
            guard report.nativeProbePassed else { throw failure() }
            try write(report, to: output.appendingPathComponent("evidence-native.json"))
            progress("PASS evidence_native_two_boots=true four_original_bodies=true ownership=true persistence=true browser_ui_pending=true")
        } catch {
            var cleaned = true
            do { try restartReceipt?.discard() } catch { cleaned = false }
            if controller.hasMachine { do { try await controller.forceStop() } catch { cleaned = false } }
            appendBoot(); report.machineStopped = !controller.hasMachine; report.cleanupComplete = cleaned && report.machineStopped
            if created { do { try write(report, to: output.appendingPathComponent("evidence-native.json")) } catch { cleaned = false } }
            FileHandle.standardError.write(Data("FAIL evidence_stage=\(report.stage) boot=\(report.bootAttempts) machine_stopped=\(report.machineStopped) cleanup_complete=\(cleaned)\n".utf8))
            exit(1)
        }
    }
    #endif
}
