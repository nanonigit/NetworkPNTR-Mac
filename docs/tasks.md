# Phases and test gates

- [x] P0: baseline all navigation/page/API routes; requirements/design/parity and failure-test plan; live browser evidence; independent private repository.
- [ ] P1: real signed macOS app boots/stops Linux with no Docker dependency, no host shares or network; integrity failures prevent boot; start-stop-start and timeout/error paths verified; app window inspected.
- [ ] P2: guest ARTEX/PostgreSQL, persistence, authenticated vsock API, crash recovery; identical fixture data and auth behavior compared with reference; secrets/egress design and negative tests.
- [ ] P3: native LLM configuration, dashboard, chat, tasks/detail, findings/detail; same fixtures/success/error/stream/cancel; API access alone does not pass UI gate.
- [ ] P4: every remaining feature and detail tab mapped in feature-map.json; CRUD, import/export, notifications/interception/MCP/tools, language/accessibility/keyboard comparison.
- [ ] P5: licensed guest/source distribution, signed/notarized install, clean-Mac first run, migration/backup/restore, safe upgrade/rollback, performance and final whole-product parity.

Phase evidence: unit tests for invariants/state/integrity, real-VM integration outputs, browser/native screenshot pairs for each workflow, API-contract comparison against deterministic fixtures, and failure injection. Never count a pending screen as passed because its title exists in a sidebar. Do not use real external security targets in parity fixtures. Each matrix row must have source reference, controls, fixture, actions, expected output, native status, evidence and known differences before release.
