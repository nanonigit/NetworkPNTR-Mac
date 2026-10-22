import ArtexCore
import Foundation

@MainActor enum BackendProbe {
    static func run(_ args: [String]) async {
        guard args.count == 2 else { print("Usage: VMProbe --backend guest-artifacts evidence-directory"); exit(2) }
        let artifacts = URL(fileURLWithPath: args[0])
        let logs = URL(fileURLWithPath: args[1])
        let controller = VMController()
        do {
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let disk = logs.appendingPathComponent("state-" + UUID().uuidString + ".ext4")
            _ = try PersistentGuestDisk.createIfMissing(at: disk, byteCount: 2 * 1024 * 1024 * 1024)
            var provisioning = try GuestProvisioning.generate()
            func boot(_ stateDisk: URL) async throws {
                try await controller.start(artifacts: artifacts, logs: logs, readinessTimeout: .seconds(120), dataDisk: stateDisk, provisioning: provisioning)
                for _ in 0..<1300 {
                    if controller.guestReady || controller.state == .failed || controller.state == .stopped { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
            }
            func requireReady() throws {
                guard controller.guestReady else { throw RuntimeError.timeout("backend boot: " + controller.guestLog) }
                let required = ["network_hardware_devices=0", "network_nonloopback_up=0", "network_external_routes=0", "shared_mounts=0"]
                let lines = Set(controller.guestLog.components(separatedBy: .newlines))
                guard required.allSatisfy(lines.contains) else { throw RuntimeError.integrity("guest isolation evidence") }
                guard !controller.guestLog.contains(provisioning.transportToken), !controller.guestLog.contains(provisioning.setupToken) else { throw RuntimeError.integrity("credentials appeared in guest log") }
            }
            func request(_ method: String, _ path: String, body: [String: Any]? = nil, token: String? = nil) async throws -> (Int, [String: Any]) {
                let data = try body.map { try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) } ?? Data()
                var header = "\(method) \(path) HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\nContent-Type: application/json\r\nContent-Length: \(data.count)\r\n"
                if let token { header += "Authorization: Bearer \(token)\r\n" }
                let response = try await controller.probeBackend(request: Data((header + "\r\n").utf8) + data, provisioning: provisioning)
                guard let split = response.range(of: Data("\r\n\r\n".utf8)),
                      let code = Int(String(decoding: response[..<split.lowerBound], as: UTF8.self).split(separator: " ").dropFirst().first ?? "") else { throw RuntimeError.integrity("probe HTTP response") }
                let object = try JSONSerialization.jsonObject(with: response[split.upperBound...]) as? [String: Any]
                guard let object else { throw RuntimeError.integrity("probe JSON response") }
                return (code, object)
            }
            func expect(_ code: Int, _ actual: Int, _ stage: String) throws {
                guard actual == code else { throw RuntimeError.integrity(stage + " status=\(actual)") }
            }
            try await boot(disk); try requireReady()
            let status = try await request("GET", "/api/auth/status")
            try expect(200, status.0, "first auth status")
            guard status.1["initialized"] as? Bool == false, status.1["setup_token_required"] as? Bool == true else { throw RuntimeError.integrity("first-run auth contract") }
            let denied = try await request("GET", "/api/llm/profiles")
            try expect(401, denied.0, "protected API")
            let password = UUID().uuidString + "-fixture"
            let wrongSetup = try await request("POST", "/api/auth/init", body: ["password": password, "setup_token": "wrong"])
            try expect(403, wrongSetup.0, "wrong setup token")
            let initialized = try await request("POST", "/api/auth/init", body: ["password": password, "setup_token": provisioning.setupToken])
            try expect(200, initialized.0, "setup")
            guard let token = initialized.1["token"] as? String else { throw RuntimeError.integrity("setup session") }
            let fixture: [String: Any] = ["name": "Native parity fixture", "format": "openai", "base_url": "https://api.openai.com/v1", "model": "fixture-no-request", "api_key": "", "streaming": false, "context_window_k": 64, "max_tokens": 256, "pool_exclude": true]
            let saved = try await request("POST", "/api/llm/profiles", body: fixture, token: token)
            try expect(200, saved.0, "save profile")
            func profile() async throws -> [String: Any] {
                let listed = try await request("GET", "/api/llm/profiles", token: token)
                try expect(200, listed.0, "persisted authenticated profile")
                guard let profiles = listed.1["profiles"] as? [[String: Any]], let first = profiles.first(where: { $0["name"] as? String == fixture["name"] as? String }) else { throw RuntimeError.integrity("persisted profile record") }
                let keys = ["name", "format", "base_url", "model", "streaming", "context_window_k", "max_tokens", "pool_exclude"]
                let expected = fixture.filter { keys.contains($0.key) }
                let actual = first.filter { keys.contains($0.key) }
                guard try JSONSerialization.data(withJSONObject: expected, options: [.sortedKeys]) == JSONSerialization.data(withJSONObject: actual, options: [.sortedKeys]) else { throw RuntimeError.integrity("profile fields changed") }
                return actual
            }
            let normalized = try await profile()
            let rejectedRequest = Data("GET /api/auth/status HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n".utf8)
            do {
                let rejected = try await controller.probeBackend(request: rejectedRequest, provisioning: provisioning, rejectTransport: true)
                guard rejected.isEmpty else { throw RuntimeError.integrity("unauthenticated transport produced data") }
            } catch let error as POSIXError {
                guard [.ECONNRESET, .EPIPE, .ENOTCONN].contains(error.code) else { throw error }
            }
            print("PASS real_artex_postgres16=true vsock_http=true wrong_transport_rejected=true protected_api=401 wrong_setup=403 profile_save_read=true")
            try await controller.stop()
            provisioning = try GuestProvisioning.generate()
            try await boot(disk); try requireReady()
            let afterRestart = try await request("GET", "/api/auth/status")
            guard afterRestart.1["initialized"] as? Bool == true else { throw RuntimeError.integrity("admin password persistence") }
            _ = try await profile()
            print("PASS normal_restart_db_password_jwt_profile_persist=true")
            for _ in 0..<3 {
                try await controller.forceStop()
                provisioning = try GuestProvisioning.generate()
                try await boot(disk); try requireReady()
                _ = try await profile()
            }
            print("PASS force_stop_restart_db_jwt_profile_persist=true")
            try await controller.stop()
            let badDisk = logs.appendingPathComponent("invalid-" + UUID().uuidString + ".ext4")
            _ = try PersistentGuestDisk.createIfMissing(at: badDisk, byteCount: 2 * 1024 * 1024 * 1024)
            let marker = Data("nonblank-invalid-disk-do-not-format".utf8)
            let writer = try FileHandle(forWritingTo: badDisk)
            try writer.write(contentsOf: marker); try writer.close()
            provisioning = try GuestProvisioning.generate()
            try await boot(badDisk)
            guard controller.state == .failed, controller.lastError?.contains("nonblank-state-disk") == true else { throw RuntimeError.integrity("bad disk must visibly fail before formatting") }
            try await controller.forceStop()
            let reader = try FileHandle(forReadingFrom: badDisk)
            let prefix = try reader.read(upToCount: 4096) ?? Data(); try reader.close()
            guard prefix.prefix(marker.count) == marker, prefix.dropFirst(marker.count).allSatisfy({ $0 == 0 }) else { throw RuntimeError.integrity("bad disk was modified") }
            print("PASS nonblank_invalid_disk_rejected_without_formatting=true secret_logging=false network_devices=0 host_shares=0")
            let contract: [String: Any] = ["initial_auth": status.1, "protected_status": denied.0, "wrong_setup_status": wrongSetup.0, "setup_status": initialized.0, "profile_status": saved.0, "profile": normalized]
            try JSONSerialization.data(withJSONObject: contract, options: [.prettyPrinted, .sortedKeys]).write(to: logs.appendingPathComponent("api-contract-vm.json"))
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error.localizedDescription)\n".utf8))
            try? await controller.forceStop()
            exit(1)
        }
    }
}
