# Chat foundation verification

Status: C1 finite service/store implemented; C2 finite CRUD/empty transcript subset verified on the signed app VM and disposable pinned backend. Native chat UI, populated guest history, successful AI send/stop, upload/SSE and external UI acceptance remain pending. feature-map remains pending. See chat-design.md.

## Evidence and chronology

1. Seven model tests cover replay/out-of-order and history-page merging, all current and unknown event kinds, tool pairing/metadata/detail, exact signed/unsigned 64-bit identifiers, nullable LLM/running/pin state and invalid required data. The initial test build failed because ChatActivity was not implemented (RED 4505d7c); the models then passed the first seven tests (GREEN 50e60ac).
2. Read-only review and a source comparison found empty pinned_at fallback differed from the browser. A targeted executed test reproduced XCTAssertFalse failure at ChatModelsTests:58 (RED 3395e8e). Swift had checked optional presence, while JavaScript Boolean(empty string) is false. Explicit pinned=false must continue to override a nonempty timestamp.
3. Repair uses pinned ?? !(pinnedAt?.isEmpty ?? true). The added empty-timestamp case passes together with all 49 Swift tests. Instrumentation records 37/37 ChatModels lines and 36/36 regions covered, in evidence/chat/models-verification.json. Branch coverage and whole-product coverage are not inferred. The read-only review approved the correction but did not rerun tests; local tool output is the test evidence.

## Causal analysis and prevention

Why mismatch? Presence was used instead of truthiness. Why plausible? A valid database timestamp is normally nonempty. Why missed by the original positive test? It covered missing/valid timestamps and explicit false but not an empty string. Why relevant at a port boundary? Optional Swift strings and JavaScript Boolean have different semantics. How prevent recurrence? Use a source-derived table for null/missing/empty/nonempty/explicit-false cases, retaining the runtime RED and regression case. Fishbone axes: language semantics, wire nullability, legacy records and fixture boundary coverage.

No live browser records were created or changed. The earlier read-only empty browser screenshot is a baseline, not proof of equivalent populated native UI. Finite API/state evidence is recorded below. Populated guest history, successful AI send/stop, files, citations, SSE, approvals, Japanese IME and cloud egress remain open.

## C1 and finite C2 checkpoint

All 66 Swift tests and 28 Python tests pass. Of these, 24 Swift chat tests cover 7 model, 6 service and 11 store scenarios. Service tests exercise exact route/body/null encoding, Unicode scalar bounds, negative/malformed responses, partial batch deletion and sanitized errors. Store tests suspend requests to check nonoverlap, selection/stop/reset invalidation, older/tail merging, submitted versus edited drafts, confirmed mutation versus refresh failure, final 1000-event draining and resumption. The 49-test model artifact above is a historical checkpoint, not the current total.

Measured coverage in core-verification.json: ChatModels 37/37 lines (100%), ChatService 106/110 (96.36%), ChatStore 197/209 (94.26%). Regions are respectively 100%, 93.69%, 82.66%. Branch coverage and whole-product coverage are not measured/inferred.

The signed debug app using source kernel 6.12.114-artex, one vCPU, zero NICs and zero host shares boots a fresh private VM; its authenticated ChatService passes create/rename, pin/unpin, explicit-null profile clear/restore, empty history/delta, missing-detail empty response, idle stop, invalid empty send/profile, deduplicated partial batch delete and single delete/cleanup. No successful AI turn is started. The remaining empty database then passes auth/LLM persistence, logout/login and cooperative stop-during-boot checks. Normalized native-results explicitly retain ui_click_workflow_verified=false.

The same ten finite contract groups match a separate pinned reference backend/PostgreSQL on a private internal Docker network with no host mounts/ports, unprivileged app, dropped capabilities and disposable tmpfs data. Only the newly created containers/network are removed. The user's existing browser server/data are untouched. Docker Desktop remained running for reference testing; this does not prove a clean Mac installation without Docker Desktop. Reference fixture imports have no network effects, and host/unmarked-Linux execution is rejected before HTTP.

Artifacts: evidence/chat/finite-contract-vm.json, finite-contract-reference.json, finite-comparison.json, finite-native-results.json and core-verification.json. Raw logs/state/session material remain ignored. This finite C2 subset does not satisfy populated history/delta, running cancellation or native UI gates.

## Review-driven regressions

Runtime RED da2b6c7 reproduced three assertions when an old idle delta suppressed an accepted turn. GREEN 28d8e6d adds a mutation revision and a sequential follow-up inside the same delta slot. RED 6a46acb reproduced three assertions when a send resumed transcript work after stop; GREEN 539a5ab checks lifetime/cancellation after the list await. Reference boundary RED f7d3827 had two failures and one error with mocked HTTP only; GREEN bdd01e5 enforces Linux/UID/explicit disposable marker and main-only execution. Details and recurrence controls are in bugs/chat-state-investigation.md. Read-only review is separate from the locally executed tests.
