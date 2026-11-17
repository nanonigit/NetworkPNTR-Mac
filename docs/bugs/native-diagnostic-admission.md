# Diagnostic launch admission

Status: three ordering regressions pass. Signed relaunch admitted diagnostics and reached VM boot; the guest then panicked before authentication.

Reproduction: start the signed development app with `--native-diagnostics NEW_PRIVATE_DIRECTORY --native-review --no-llm-review`. The process remained alive and the native window appeared, but no diagnostic directory or VM was created. The signed-out AI connections screen correctly disabled authorization.

Expected: a requested diagnostic starts once when the app has launched and SwiftUI has attached its runtime, using only the requested disposable state directory.

Root cause supported by source, ordering tests and signed admission: the launch callback scheduled a single delayed weak-runtime lookup. If SwiftUI attachment occurred after that lookup, the guard returned with no subsequent trigger. A fixed delay did not establish runtime ownership or readiness.

Five whys: no diagnostic ran because its runtime was absent at the one lookup; attachment can occur later because scene appearance and launch are separate events; no later trigger existed because startup was tied only to launch; the delay assumed event order instead of modeling both prerequisites; previous plan/fixture tests did not cover their callback ordering. Contributing factors were timing, weak ownership, missing lifecycle admission and an incomplete signed startup gate.

Timeline: live CLI launch stayed idle; the unsigned-in screen was inspected; observing an app handle after quitting reactivated a normal instance, which reached a fresh setup screen. No credential was entered; that VM was stopped normally. Future termination checks use process inventory instead of observing the terminated app handle.

Fix: a DEBUG-only admission gate waits for both launch and runtime attachment in either order, admits once before scheduling, and waits at most two seconds for an existing visible window before the existing diagnostics run. No new UI action starts diagnostics, and ordinary launches without a requested directory remain unchanged. Repeated callbacks cannot re-run a failed or admitted test automatically.

Verification: runtime-after-launch, runtime-before-launch and ordinary-launch regressions pass. Signed fixture boot, external UI permission/cancellation/revocation checks, real MCP/VM readback and stopped-log audit remain separate gates. This fix does not imply those features have passed.

The signed repaired launch created the private diagnostic state and rendered the native window. The guest reached state_zero_check, then kernel6.12.114-0-virt panicked after PID1 exited with0x0000000b. The machine stopped and raw counter-evidence remains private. This proves launch admission, not guest stability or the authenticated MCP workflow. See [receipt](../../evidence/mcp/native-diagnostic-admission.json).
