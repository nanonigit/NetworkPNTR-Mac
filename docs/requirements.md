# Requirements and completion goal

Build a native macOS ARTEX application, a separate private repository `nanonigit/artex-mac`. On this Apple Silicon Mac, launch, operate, stop, update and recover ARTEX without browser, Docker Desktop, terminal commands or a manually started server. SwiftUI owns the user interface; autonomous shell execution and PostgreSQL run only in an app-managed Linux VM.

## Release acceptance criteria

R1. All 21 upstream navigation features, every page/detail route and their controls are accounted for in feature-map.json; no functional omission is silently accepted. Final release requires equivalent workflows, not just similar-looking screens.
R2. Browser commit e75ae371ad777ffd1eecdd28d2781a6519b05591 is the reference. Compare identical fixtures, validation, errors, empty states, progress/SSE, cancellation, mutations, exports and persistence. Each case has separate automated/API and human-observed UI evidence.
R3. Native sidebar preserves Features/System hierarchy, wording, ordering and task/detail relationships. Native menus, keyboard access and window behavior may improve ergonomics; differences require a documented reason and parity case. Use Lazyweb as secondary evidence; upstream is authoritative.
R4. No host shell execution by agents, no Docker socket, no shared host directories, no arbitrary host RPC. Guest networking is off initially. Later grant explicit egress/target policies; cloud credentials never appear in logs or Git.
R5. Start/stop/restart, failure, crash, disk-full and update rollback are tested. Persist data on a guest-owned disk. Existing browser installation remains a separate preserved reference; migrate only via a tested explicit import.
R6. Package a locally runnable .app; production signing, notarization, clean-Mac install, licenses and verified restore are final-phase gates. Phase 1 supports Apple Silicon only, macOS 15+; Intel support is not claimed.
R7. No fake task/LLM results or phase-completion claims. Distinguish lifecycle state, guest-ready evidence and API readiness. A new server response does not prove a native workflow works.

The current authorized first milestone is Phase 0 documentation and Phase 1 executable VM proof. Later phases remain required by the full goal, and cannot be marked complete by a mock UI or browser wrapper.

A3 content-verification extension: hash every byte of the actual near128MiB attachment through authenticated vsock using bounded memory. Preserve generic JSON4MiB limits, session revision isolation, cancellation/VM-stop descriptor ownership and the fixed browser. One successful response must have the expected metadata size and exact HTTP framing; incomplete/oversized/encoded/ambiguous responses fail. This proves received bytes, not a filesystem snapshot under concurrent guest writes. Full native attachment UI and download/export workflows remain separate acceptance gates.
