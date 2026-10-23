# Phases and test gates

- [x] P0: baseline all navigation/page/API routes; requirements/design/parity and failure-test plan; live browser evidence; independent private repository.
- [ ] P1: real signed macOS app boots/stops Linux with no Docker dependency, no host shares or network; integrity failures prevent boot; start-stop-start and timeout/error paths verified; app window inspected.
- [ ] P2: guest ARTEX/PostgreSQL, persistence, authenticated vsock API, crash recovery; identical fixture data and auth behavior compared with reference; secrets/egress design and negative tests.
- [ ] P3: native LLM configuration, dashboard, chat, tasks/detail, findings/detail; same fixtures/success/error/stream/cancel; API access alone does not pass UI gate.
- [ ] P4: every remaining feature and detail tab mapped in feature-map.json; CRUD, import/export, notifications/interception/MCP/tools, language/accessibility/keyboard comparison.
- [ ] P5: licensed guest/source distribution, signed/notarized install, clean-Mac first run, migration/backup/restore, safe upgrade/rollback, performance and final whole-product parity.

Phase evidence: unit tests for invariants/state/integrity, real-VM integration outputs, browser/native screenshot pairs for each workflow, API-contract comparison against deterministic fixtures, and failure injection. Never count a pending screen as passed because its title exists in a sidebar. Do not use real external security targets in parity fixtures. Each matrix row must have source reference, controls, fixture, actions, expected output, native status, evidence and known differences before release.

Backend checkpoint: see docs/phase2-verification.md. Guest boot, authenticated vsock, data/auth persistence and five reference API fixture contracts pass; native auth integration is implemented but intermittent guest startup/recovery failures keep the runtime gate open. Streaming/egress, native-click/visual acceptance and broader parity remain pending.

P3 LLM checkpoint: typed profile/pool/retry services and native screens implemented; 11 normalized contract groups match the pinned reference. External create/edit/validation/keyboard-save/activation checks pass. Full LLM interaction/cloud/visual gates remain open; see docs/llm-settings-verification.md.

P3 dashboard checkpoint: all visible sections and 11 authenticated read routes are connected. 12 nonempty token scenarios match an independent browser calculation and disposable pinned reference. Partial external UI interactions passed; populated visual pairs, traffic capture and remaining error/accessibility/runtime gates stay open. See docs/dashboard-verification.md.

Portable-kernel work: pinned source/config/compiler package inventory and offline build/profile tools are implemented with 24 Python regression tests. The first offline source build, six-boot VM lifecycle suite, signed native auth/LLM/dashboard diagnostics and reference comparisons pass. Independent same-host builds match kernel/config/build-report hashes. License contents match but archive directory times differ; whole-builder identities differ and cross-host/package reproducibility is not accepted. Runtime promotion and reliability acceptance remain open. See docs/kernel-build-verification.md. See docs/kernel-build-design.md and docs/bugs/guest-boot-investigation.md.

P3 chat checkpoint: C1 typed finite services/state store pass 24 scoped tests (66 Swift total). C2 basic CRUD/empty transcript has ten matching groups on the signed source-kernel VM and disposable pinned reference. 28 Python tests pass, including reference isolation. Populated guest history, AI running/send/stop, UI and advanced parity remain pending. See docs/chat-verification.md and docs/bugs/chat-state-investigation.md.

P3 chat populated checkpoint: latest 200 + older five from 205 fixed events, overlapping delta and final six to 211 match ten pinned-reference groups. Two fresh signed native runs pass; the second proves exact full-history/detail persistence after VM restart and authenticated cleanup before dashboard seeding. Current local regression: 66 Swift / 34 Python. Chat UI and successful AI/running stop remain open. See docs/chat-verification.md.

P3 C3 checkpoint: native rail/transcript/composer implemented; partial external browser/native comparison and scroll/draft/IME regressions pass. 75 Swift (74 core + 1 AppKit) and34 Python tests pass. Chat is in_progress; native running stop, multi-delete confirmation, cloud response, advanced controls and full visual/accessibility gates remain pending. See chat-verification.md.
