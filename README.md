# NetworkPNTR Mac

[English](README.md) | [日本語](README.ja.md)

**Login-free startup:** The ordinary and Cloud Preview apps open the dashboard without an app ID or password. The Mac app automatically authenticates to its dedicated Linux VM and retains existing local data. Both variants passed real startup and restart checks. The Cloud Preview diagnostic reached OpenAI, Anthropic, Gemini and Groq and verified rejection of an invalid test key. [Verification](docs/local-session-native-verification.md)

Repository: [nanonigit/NetworkPNTR-Mac](https://github.com/nanonigit/NetworkPNTR-Mac).

PNTR stands for penetration testing. NetworkPNTR Mac aims to help individuals and organizations find vulnerabilities and bugs in systems they own or are authorized to assess, and strengthen their own defenses.

Native SwiftUI macOS application with an app-managed isolated Linux VM. **Development milestone: isolated VM proof and partial native feature migration; not a complete client.** LLM settings and the dashboard are implemented and under comparison; Chat core UI is also implemented with partial comparison. The first Tasks list/detail, creation, categories and bulk surfaces are wired to finite guest APIs, with unit/offscreen checks and separate catalog runtime comparison; Basic Findings list/group/asset/detail and triage controls are also wired with controlled/offscreen checks; 16 feature screens remain unimplemented. All 21 workflow acceptance gates are still open. The existing Docker browser instance is preserved independently.

See [native Findings evidence](docs/findings-ui-verification.md) for basic controls, ownership regressions and remaining visual/runtime/advanced gates.

Findings fixed-data seeding has real PostgreSQL rollback/readback/replay evidence. See [seed verification](docs/findings-seed-verification.md).

The native VM now passes one actual three-boot basic Findings experiment and matches an independent frozen-backend API reference. Initial/persisted100-read checks, partial-PATCH500, deletions, source bindings and cleanup pass. This does not accept visible UI, all Findings scenarios or kernel reliability. See [runtime verification](docs/findings-runtime-verification.md).

## Current evidence

- Apple Virtualization.framework really boots ARM64 Linux and cooperatively stops it, twice in sequence, without Docker, host shares, NICs or persistent disks.
- Modified kernel is rejected before VM creation. An actual guest that never emits readiness times out visibly and recovers through force stop.
- Login-free startup checkpoint: 1,227 Swift tests (1,226 passed, one skipped) and 222 Python tests passed without failures. See the verification notes for remaining UI and runtime acceptance checks.
- Native application .app is built, locally ad-hoc signed with the virtualization entitlement and launched. Its developer harness runs the VM service from the real app and records readiness/shutdown. External CUA verified native LLM creation/editing, numeric validation, Return-key save and active-profile protection. The connection later failed; full click/visual acceptance is still pending. Content-view snapshots are diagnostic only and have layer-compositing limitations; they are not signed off as UI parity.

The separate backend acceptance guest now boots pinned NetworkPNTR and PostgreSQL 16 with authenticated vsock and a private persistent disk. Real normal/forced restarts preserve authentication and an LLM fixture. Five normalized API contract cases match a disposable pinned browser backend. See [Phase 2 evidence](docs/phase2-verification.md). The app bundles the backend by default. Earlier verification used native setup/login/logout with a Keychain session. Two-vCPU experiments exposed intermittent kernel faults. A one-vCPU direct-root diagnostic profile passed repeated native auth runs; a separate database recovery readiness race was repaired and three forced recoveries passed. Release reliability is not accepted; see [the investigation](docs/bugs/guest-boot-investigation.md).

A separately source-built, hash-pinned Linux kernel candidate passed real VM recovery and signed native service/reference comparisons. Two fresh same-host builds produce identical kernel/config hashes; release reliability, cross-host/package reproducibility and UI parity remain open. See [source-kernel verification](docs/kernel-build-verification.md).

## Build and test (Apple Silicon, macOS 15+, Xcode/Swift 6.1+ toolchain, Python 3)

```sh
# Prepare the real backend first (developer-only Docker build):
python3 script/prepare_backend.py --source /path/to/pinned/browser-source
python3 script/build_local_session.py --source /path/to/pinned/browser-source --profile default --artifacts guest/backend-artifacts --output guest/native-session-artifacts
./script/build_and_run.sh --verify
swift test
./script/test_vm.sh
python3 script/check_baseline.py /path/to/pinned/browser-source
# Optional backend acceptance build (requires the pinned local browser image and Docker):
./script/test_backend.sh /path/to/pinned/browser-source
```

The app is staged at `dist/NetworkPNTR Mac.app`. Developer backend construction uses a pinned Linux build container and verifies boot-artifact hashes; Linux executables never run on macOS. The application runtime uses bundled guest artifacts and calls neither Docker, Python nor a manually launched server. It creates its own private persistent disk. Quit the app normally before replacing its bundle, allowing its VM to flush and stop. This is an investigation build, not a stable release.

The runtime screen starts and stops the dedicated backend VM. The app authenticates automatically and the ordinary sidebar omits the account screen. The LLM screen connects actual profile, rotation and retry services; see [LLM comparison evidence](docs/llm-settings-verification.md). The dashboard reads actual tasks, activity, findings, usage, assets and system status; its 12 nonempty token scenarios match a disposable pinned reference and independent browser calculations. See [dashboard evidence](docs/dashboard-verification.md). The parity screen tracks incomplete acceptance, and the remaining feature entries show explicit migration placeholders. No browser-version API key, password or data is imported. Repeated boot reliability, full native workflow comparison, authenticated cloud inference and distribution signing and notarization remain open.

## Plan and comparison

Read docs/requirements.md, docs/design.md, docs/tasks.md. Browser baseline: the frozen browser source commit e75ae371ad777ffd1eecdd28d2781a6519b05591. `docs/feature-map.json` tracks 21 primary features, 27 page source files and 243 handlers in the main router. The inventory is a coverage baseline, not proof all controls have been migrated. The matching catalog is bundled into the app and checked by tests.

Maintain identical fixtures and expected outcomes before each migrated feature passes its phase. Capture browser/native controls, error/empty/progress/cancel and restart behavior separately from API tests. No external real targets or paid AI calls are needed for the first phase. Lazyweb reference search: https://www.lazyweb.com/agentic-search/d85df937-aa86-420d-ad7f-e702652210e7 (finalization was rate-limited).

Source is under AGPL-3.0; see LICENSE and THIRD_PARTY.md. Large generated guest artifacts and raw logs are excluded from Git. This is a development build, not a notarized release.

Chat finite API/state core, ten basic CRUD groups and ten populated-history groups are verified. The signed app restores all 211 fixture events and their full detail after VM restart. Native chat core UI has partial external comparison; successful AI send/running-stop and full acceptance remain pending. See [chat verification](docs/chat-verification.md).

Latest attachment checkpoint: the full134,217,517-byte content SHA matches the signed native VM and pinned disposable browser backend. Actual VZ upload cancellation and VM stop during partial transfer pass with an active-socket witness, authenticated restart and owned cleanup.190 Swift/45 Python tests pass. Typed upload/create/text handoff now passes an actual VM/control run and six pinned backend metadata/failure groups; four source-derived browser send cases remain verified. The first new VM attempt failed in blank checking with kernel memory warnings and is retained as counter-evidence. Picker/cards, download cancellation, multipart-spill cancellation, process-memory measurement and runtime reliability remain open. See [chat verification](docs/chat-verification.md) and evidence/chat/attachment-handoff-verification.json.


## English and Japanese UI

The toolbar switches the shared native shell between English and Japanese. Actual switching preserves the active chat draft, attachment card and selection; a new app process retains the chosen language. Feature interiors and backend output-language synchronization are still being migrated, so this is not complete bilingual support. See [verification](docs/localization-shell-verification.md).

Edit `Sources/NetworkPNTRCore/Resources/Localizable.xcstrings` as the translation source, then run:

```sh
python3 script/export_localizations.py
python3 script/export_localizations.py --check
swift test
```

The generated en/ja `.strings` files are committed for SwiftPM build-system compatibility. Do not edit them by hand. CI and the app build wrapper reject stale generated resources.

Tasks checkpoint T3: native list/detail, search/status/sort, rename/pin/pause-resume/delete and five cleanup choices are wired; captured dialog IDs protect queued confirmation, dismissal and field callbacks. Actual VM/browser/native click/visual comparison is pending. Creation, bulk/category/archive and advanced task workflows remain open. See [Tasks UI verification](docs/tasks-ui-verification.md).

Tasks checkpoint T4: native creation covers all 12 request fields with ordered models, associations, minute limits and interception rules; template overwrite is confirmed and raw Unicode bytes are preserved. 331 Swift cases pass with one existing AX skip; 52 Python pass. Real creation/validation/browser comparison, staging uploads and template/category management remain open. See [creation verification](docs/tasks-create-verification.md).

Boot diagnostic checkpoint B1 separates blank-check execution failure from nonblank data and audits the complete bounded log. Old/new single-boot preflights pass; earlier intermittent kernel faults remain unresolved and the candidate is not promoted. See [verification](docs/boot-preflight-verification.md).

Task staging checkpoint T5 adds the authenticated UUID upload transport with exact guest paths, complete metadata validation and shared cancellation/auth guards. Picker/model/description manifest and live browser/VM comparison remain open. See [verification](docs/tasks-staging-verification.md).

Task staging T6 wires the native picker, owned upload state/progress, cancellation and bilingual description manifest.126fixed-browser pure-function outputs match. Actual native clicks/security-scoped file transfer, VM/browser persistence and full parity remain open. See [verification](docs/tasks-staging-ui-verification.md).

Staging T7 passes one actual native VM transfer/readback run:8saved versions and both manifests equal the pinned disposable reference, with no clobbering. Earlier reference setup failures are retained; UI/task creation/restart reliability remain open. See [runtime verification](docs/task-staging-runtime-verification.md).
