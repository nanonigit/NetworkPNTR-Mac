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

Portable-kernel work: pinned source/config/compiler package inventory and offline build/profile tools are implemented with 24 Python regression tests. Actual source-kernel compilation, VM lifecycle tests and independent rebuild comparison are in progress; no runtime promotion follows from the tooling tests. See docs/kernel-build-design.md and docs/bugs/guest-boot-investigation.md.
