# Chat state and fixture boundary investigation

Scope: the new finite native chat core and developer-only reference harness. No user data loss or host backend mutation was observed. This is backend/state/infrastructure work; additional Lazyweb UI research is out of scope. Uses the MUSUBI Bug Hunter reproduction, causal analysis, repair, verification and recurrence-prevention workflow.

## Timeline and evidence

1. C1 service and store tests went RED before implementation (00c3376/979df8b), then GREEN (90672a8/4ba3665).
2. Stop/resume lost final events when list running=false: executed RED 0c37634, GREEN ed669bb preserves a reconciliation demand on resume.
3. Read-only review identified an accepted-send overlap: suspend an old idle delta; accept another send; complete the old delta. RED da2b6c7 executed ten tests and failed three assertions: one request instead of two, old messages and old cursor. GREEN 28d8e6d passes after tracking tail mutation revisions.
4. Follow-up review found post-stop restart: suspend the accepted send's list refresh; stop; release that list. RED 6a46acb executed eleven tests with three failed assertions (new request, new messages, cleared demand). GREEN 539a5ab rechecks lifetime and cancellation before its follow-up.
5. Reference fixture review found import/host execution contacted loopback. Tests mock HTTP, so no real host request occurs. RED f7d3827: two failures and one error. GREEN bdd01e5: main-only execution, Linux/UID1000/explicit disposable marker checks before network, and four fixture tests pass.
6. Full local regression: 66 Swift and 28 Python tests pass; signed VM CRUD and ten disposable-reference contract groups agree. Final read-only reviewer approved source changes and did not rerun tests or access runtime resources.

## 5 Whys

Why missing new messages? An old idle delta cleared the new turn's polling demand. Why did it win? Only conversation/lifetime identity was checked; both requests belonged to the same selected conversation. Why insufficient? A send acknowledgement changes transcript freshness within that selection. Why was ordering untested? Initial cases covered selection changes and send failures separately. Prevention: suspend an old delta across a real accepted-mutation boundary, preserve the newer revision, then fetch sequentially without a second overlapping delta slot.

Why could work resume after stop? Send awaited a list refresh, then started a new delta. Why did invalidation not block it? The list guarded its own response, but its caller did not recheck after await. Why was the selected conversation retained? Stop intentionally permits later foreground reconciliation. Why was that mistaken for authorization to continue? Retained selection was the only follow-up guard. Prevention: validate the originating lifetime and cancellation at every continuation boundary before launching dependent work.

Why could a reference script contact the host? It ran its HTTP workflow at import/top level. Why was the boundary assumed? Its intended caller uses docker exec. Why insufficient? The file is also executable/importable locally and loopback means different machines in those contexts. Why missed? Initial CLI smoke coverage checked dispatch, not executable isolation. Prevention: main-only workflow, explicit container-only preconditions, and mocked host/unmarked/import regression tests.

## Fishbone

Concurrency: awaited request ordering, mutation revisions and nonoverlap. Lifecycle: stop retains selected data but invalidates prior continuations. Wire contract: running is a snapshot, never a guarantee that a later accepted turn is represented. Tool boundary: loopback changes meaning across host/container; documentation is not an executable guard. Testing: use suspended requests and fake HTTP to expose these timing and boundary conditions without touching user data.

## Recurrence controls and limits

The new tests run in existing CI. Mutation generations cannot clear a newer reconciliation demand; post-await work must match its lifetime. A full final 1000-event page demands another delta even if running=false. Confirmed sends remain confirmed when refresh fails, preventing duplicate retries; edited drafts survive. Reference imports are inert and host execution fails before HTTP. Credentials/raw backend errors are not stored in normalized evidence. Python uses only the standard library and the Swift package has no third-party dependencies, so npm/pip dependency audits do not apply.

No product UI, populated guest transcript, successful AI send, running cancellation, upload/SSE, cloud egress or clean-Mac distribution acceptance is inferred. Those gates remain in chat-design.md and tasks.md.

## Populated-fixture libpq boundary regression

Read-only review of the new history seed found that inherited PGHOSTADDR can select an actual remote address even when PGHOST is explicitly set to loopback. PGSERVICE/PGOPTIONS can likewise retain unintended connection/schema configuration. The same pattern existed in the dashboard seed. Runtime RED 0f6e0b4 used mocked psql and deliberately hostile PGHOSTADDR/PGSERVICE/PGSERVICEFILE/PGOPTIONS; two tests failed without contacting any database. GREEN ac57d2f removes inherited PG* variables before setting the fixed connection fields in both scripts; all six new seed tests pass.

5 Whys: the loopback DSN was validated, but the psql child inherited a second address source; libpq gives PGHOSTADDR connection significance; the original fixture environment copied the parent environment; tests had cleared it and therefore missed hostile inheritance; prevention is a sanitized libpq environment plus negative inheritance tests. Fishbone axes: subprocess inheritance, libpq address precedence, fixed SQL transaction scope and missing hostile-environment coverage. The SQL remains fixed and rejects pre-existing non-fixture activity/tasks/findings/assets within a transaction. This is fixture hardening, not proof of general guest cloud/egress acceptance.

## C3 draft/IME/viewport regressions

Reproduction: first-send creation awaits initial history; edit the draft or change selection during that await. REDb3f988f demonstrated lost/overwritten edits. An AppKit marked-text callback from the old editor could target the newly selected conversation (REDec522fb). GREEN69a4b3a transfers the draft before awaiting history and binds each editor to an explicit conversation ID; tests retain the originally submitted message while preserving newer edits. The actual NSTextView component regression passes.

Five Whys: mutable current-selection draft binding -> asynchronous creation/IME callback crosses selection change -> callback resolves current rather than original identity -> state ownership implicit -> no suspended-await/marked-text case in initial tests. Fishbone: identity, asynchronous lifetime, AppKit delegate callbacks, test boundaries. Prevention: keyed draft access, explicit handoff before await, component-level marked-text regression and suspended transport tests.

External RED48981f5: loading older11 messages changed top event12 to2. Immediate scroll restoration ran before SwiftUI's new lazy layout settled. Scroll target layout and a retained anchor restore event12; external native retest passes. Five Whys: prepend changes layout -> restoration issued against old geometry -> no stable visible identity -> asynchronous state/layout assumed synchronous -> only model merge tests existed. Fishbone: layout lifecycle, lazy rows, scroll identity, missing native interaction. Timeline: populated native review; RED screenshot; layout/anchor repair; rebuilt app; same fixture/action externally retested GREEN. This does not establish all scroll/resize/VoiceOver behavior.
