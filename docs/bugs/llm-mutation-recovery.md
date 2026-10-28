# LLM write recovery: five-stage record

## 1. Reproduction

Initial tests failed to compile because the store lacked stop/resume, unknown-revision and acknowledgement APIs (db2de38). Original six ownership cases then passed with all28 LLM tests (c16fd45). Expanded tests exposed two failed stale-review assertions and a signal11 crash during synchronous read-loading Observation departure (6b3a35c; private local logs retained). Four missing bilingual UI keys caused one matrix failure (3c84608). After repairs36 LLM tests passed (89f6728). Reviewer found the symmetric resume reentry: bounded RED3e903fb produced two cases/three failed assertions. Correction2088822 passes38 LLM tests. No actual keys, cloud requests or guest writes.

## 2. Evidence and timeline

Cases cover six mutation families, preflight validation, post-handoff cancellation and late success, stop/resume pending gate, stale full reads, pool-only read vs full review, failed subsequent reload, old acknowledgement revisions, confirmed saves with failed/departed follow-up reads and synchronous lifecycle callbacks. RootView inspection subsequently found destination-local store recreation; coordinator ownership tests and window-level retention address same-session navigation separately. Real GUI navigation is still pending.

## 3. Root cause

5 Whys: repeats were allowed because mutation errors were merely displayed; no dispatch marker distinguished preflight failure from uncertain write; no retained write ticket gated reentry/departure; no explicit full-review revision gated resumption; tests focused on immediate success/error paths. Fishbone: state—busy booleans, lifetime—destination-local ownership, transport—uncooperative late returns, observation—callbacks execute before assignment, verification—no adversarial lifecycle tests. Timeline: await handoff -> depart/cancel -> server may commit -> reply cannot be accepted -> old generic error permits duplicate. This is not evidence of a provider failure.

## 4. Repair

Internal service handoff callbacks, owned read/write tickets, acquisition and lifecycle reentry guards, stable unknown revision and full-read review token. Store gates all writes until explicit acknowledgement. Same-session window coordinator retains the store across navigation; authentication-owner changes stop/release it. Three surfaces share a bilingual recovery panel outside disabled forms, with read-only overview and separate reload/resume. No auto replay, secret storage or mutation on acknowledgement.

## 5. Verification and recurrence prevention

Keep all regression cases and112-entry en/ja matrix. Do not remove the bounded resume and read-stop recursion tests. Independent core/UI/reentry review found and verified the resume correction. Probe/editor task ownership, durable uncertainty across app termination, actual browser/native interaction, sheet fit and accessibility remain unproven; software checks do not close those gates.

CI recurrence:40610980734 exposed a test-fixture phase dependency on equal-value Observation delivery. Local Xcode27 omitted the nil-to-nil callback while CI delivered it. Replace notification-driven holding with a method-specific transport hold and assert POST then GET before stopping. Retain the failed CI receipt and dedicated lifecycle tests; never treat waiting for any request as proof of the intended request phase.
