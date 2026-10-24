# ARTEX Mac

Native SwiftUI macOS application with an app-managed isolated Linux VM. **Development milestone: Phase 0, Phase 1 technical proof and Phase 2 backend acceptance checkpoint; not a complete ARTEX client.** LLM settings and the dashboard are implemented and under comparison; Chat core UI is also implemented with partial comparison; the other 18 feature screens remain unimplemented. All 21 workflow acceptance gates are still open. The existing Docker browser instance is preserved independently.

## Current evidence

- Apple Virtualization.framework really boots ARM64 Linux and cooperatively stops it, twice in sequence, without Docker, host shares, NICs or persistent disks.
- Modified kernel is rejected before VM creation. An actual guest that never emits readiness times out visibly and recovers through force stop.
- 125 Swift tests (118 core, 5 AppKit components and 2 diagnostic fixtures) and 39 Python regression tests cover inventory, lifecycle, integrity, isolation, auth, LLM services and dashboard calculations/polling.
- Native application .app is built, locally ad-hoc signed with the virtualization entitlement and launched. Its developer harness runs the VM service from the real app and records readiness/shutdown. External CUA verified native LLM creation/editing, numeric validation, Return-key save and active-profile protection. The connection later failed; full click/visual acceptance is still pending. Content-view snapshots are diagnostic only and have layer-compositing limitations; they are not signed off as UI parity.

The separate backend acceptance guest now boots pinned ARTEX and PostgreSQL 16 with authenticated vsock and a private persistent disk. Real normal/forced restarts preserve authentication and an LLM fixture. Five normalized API contract cases match a disposable pinned browser backend. See [Phase 2 evidence](docs/phase2-verification.md). The app now bundles this real backend by default and provides native setup/login/logout with a Keychain session. Two-vCPU experiments exposed intermittent kernel faults. A one-vCPU direct-root diagnostic profile passed repeated native auth runs; a separate database recovery readiness race was repaired and three forced recoveries passed. Release reliability is not accepted; see [the investigation](docs/bugs/guest-boot-investigation.md).

A separately source-built, hash-pinned Linux kernel candidate passed real VM recovery and signed native service/reference comparisons. Two fresh same-host builds produce identical kernel/config hashes; release reliability, cross-host/package reproducibility and UI parity remain open. See [source-kernel verification](docs/kernel-build-verification.md).

## Build and test (Apple Silicon, macOS 15+, Xcode/Swift 6 toolchain, Python 3)

```sh
# Prepare the real backend first (developer-only Docker build):
python3 script/prepare_backend.py --source /path/to/pinned/artex-global
./script/build_and_run.sh --verify
swift test
./script/test_vm.sh
python3 script/check_baseline.py /path/to/pinned/artex-global
# Optional backend acceptance build (requires the pinned local browser image and Docker):
./script/test_backend.sh /path/to/pinned/artex-global
```

The app is staged at `dist/ARTEX Mac.app`. Developer backend construction uses a pinned Linux build container and verifies boot-artifact hashes; Linux executables never run on macOS. The application runtime uses bundled guest artifacts and calls neither Docker, Python nor a manually launched server. It creates its own private persistent disk. Quit the app normally before replacing its bundle, allowing its VM to flush and stop. This is an investigation build, not a stable release.

The runtime screen starts/stops the dedicated backend VM; the account screen uses actual ARTEX authentication. The LLM screen connects actual profile, rotation and retry services; see [LLM comparison evidence](docs/llm-settings-verification.md). The dashboard reads actual tasks, activity, findings, usage, assets and system status; its 12 nonempty token scenarios match a disposable pinned reference and independent browser calculations. See [dashboard evidence](docs/dashboard-verification.md). The parity screen tracks incomplete acceptance, and the remaining feature entries show explicit migration placeholders. No browser-version API key, password or data is imported. Keychain restoration has passed an isolated native service diagnostic, but repeated reliability, external native clicks, controlled cloud networking, all feature workflows and distribution signing/notarization remain open gates.

## Plan and comparison

Read docs/requirements.md, docs/design.md, docs/tasks.md. Browser baseline: nanonigit/artex-global commit e75ae371ad777ffd1eecdd28d2781a6519b05591. `docs/feature-map.json` tracks 21 primary features, 27 page source files and 243 handlers in the main router. The inventory is a coverage baseline, not proof all controls have been migrated. The matching catalog is bundled into the app and checked by tests.

Maintain identical fixtures and expected outcomes before each migrated feature passes its phase. Capture browser/native controls, error/empty/progress/cancel and restart behavior separately from API tests. No external real targets or paid AI calls are needed for the first phase. Lazyweb reference search: https://www.lazyweb.com/agentic-search/d85df937-aa86-420d-ad7f-e702652210e7 (finalization was rate-limited).

Source is under AGPL-3.0; see LICENSE and THIRD_PARTY.md. Large generated guest artifacts and raw logs are excluded from Git. This is a development build, not a notarized release.

Chat finite API/state core, ten basic CRUD groups and ten populated-history groups are verified. The signed app restores all 211 fixture events and their full detail after VM restart. Native chat core UI has partial external comparison; successful AI send/running-stop and full acceptance remain pending. See [chat verification](docs/chat-verification.md).

Latest attachment checkpoint: the full134,217,517-byte content SHA matches the signed native VM and pinned disposable browser backend. Actual VZ upload cancellation and VM stop during partial transfer pass with an active-socket witness, authenticated restart and owned cleanup.157 Swift/42 Python tests and eight pinned full-upload contracts pass. Native attachment state/picker/cards, download cancellation, multipart-spill cancellation, process-memory measurement and runtime reliability remain open. See [chat verification](docs/chat-verification.md) and evidence/chat/upload-progress-verification.json.
