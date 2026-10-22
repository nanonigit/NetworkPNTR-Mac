# ARTEX Mac

Native SwiftUI macOS application with an app-managed isolated Linux VM. **Development milestone: Phase 0, Phase 1 technical proof and Phase 2 backend acceptance checkpoint; not a complete ARTEX client.** The 21 browser feature workflows are explicitly pending. The existing Docker browser instance is preserved independently.

## Current evidence

- Apple Virtualization.framework really boots ARM64 Linux and cooperatively stops it, twice in sequence, without Docker, host shares, NICs or persistent disks.
- Modified kernel is rejected before VM creation. An actual guest that never emits readiness times out visibly and recovers through force stop.
- Eight Swift unit tests and ten Python regression tests cover complete browser inventory, unsafe lifecycle transitions, digest/path/symlink rejection and no host-share/network/disk configuration.
- Native application .app is built, locally ad-hoc signed with the virtualization entitlement and launched. Its developer harness runs the VM service from the real app and records readiness/shutdown. Real button-click/visual acceptance is still pending: native computer-control connector failed. Content-view snapshots are diagnostic only and have layer-compositing limitations; they are not signed off as UI parity.

The separate backend acceptance guest now boots pinned ARTEX and PostgreSQL 16 with authenticated vsock and a private persistent disk. Real normal/forced restarts preserve authentication and an LLM fixture. Five normalized API contract cases match a disposable pinned browser backend. See [Phase 2 evidence](docs/phase2-verification.md). This guest is not yet connected to the app's native screens; the app bundle still contains the Phase 1 proof guest.

## Build and test (Apple Silicon, macOS 15+, Xcode/Swift 6 toolchain, Python 3)

```sh
./script/build_and_run.sh --verify
swift test
./script/test_vm.sh
python3 script/check_baseline.py /path/to/pinned/artex-global
# Optional backend acceptance build (requires the pinned local browser image and Docker):
./script/test_backend.sh /path/to/pinned/artex-global
```

The app is staged at `dist/ARTEX Mac.app`. Developer build downloads fixed Alpine APKs, checks SHA-256 and assembles an initial RAM disk; Linux guest executables are never executed on macOS. No Docker is required even for this proof build. Finished app bundles contain their guest boot artifacts and need neither Python nor a manually launched server for this proof. They do not yet contain ARTEX/PostgreSQL or a data disk.

The app's runtime screen can start/stop the proof guest. The parity screen lists reference workflows. Sidebar feature entries lead to explicit pending screens rather than fake working features. No browser-version API key, password or data is imported. Production distribution signing/notarization, Keychain, app/backend integration, controlled cloud networking and all native workflows remain future gates.

## Plan and comparison

Read docs/requirements.md, docs/design.md, docs/tasks.md. Browser baseline: nanonigit/artex-global commit e75ae371ad777ffd1eecdd28d2781a6519b05591. `docs/feature-map.json` tracks 21 primary features, 27 page source files and 243 handlers in the main router. The inventory is a coverage baseline, not proof all controls have been migrated. The matching catalog is bundled into the app and checked by tests.

Maintain identical fixtures and expected outcomes before each migrated feature passes its phase. Capture browser/native controls, error/empty/progress/cancel and restart behavior separately from API tests. No external real targets or paid AI calls are needed for the first phase. Lazyweb reference search: https://www.lazyweb.com/agentic-search/d85df937-aa86-420d-ad7f-e702652210e7 (finalization was rate-limited).

Source is under AGPL-3.0; see LICENSE and THIRD_PARTY.md. Large generated guest artifacts and raw logs are excluded from Git. This is a development build, not a notarized release.
