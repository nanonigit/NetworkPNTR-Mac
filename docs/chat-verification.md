# Chat foundation verification

Status: model foundation only. No chat service, store, native chat screen, send/upload/stream or external UI acceptance is claimed. feature-map remains pending. Design and later gates are in chat-design.md.

## Evidence and chronology

1. Seven model tests cover replay/out-of-order and history-page merging, all current and unknown event kinds, tool pairing/metadata/detail, exact signed/unsigned 64-bit identifiers, nullable LLM/running/pin state and invalid required data. The initial test build failed because ChatActivity was not implemented (RED 4505d7c); the models then passed the first seven tests (GREEN 50e60ac).
2. Read-only review and a source comparison found empty pinned_at fallback differed from the browser. A targeted executed test reproduced XCTAssertFalse failure at ChatModelsTests:58 (RED 3395e8e). Swift had checked optional presence, while JavaScript Boolean(empty string) is false. Explicit pinned=false must continue to override a nonempty timestamp.
3. Repair uses pinned ?? !(pinnedAt?.isEmpty ?? true). The added empty-timestamp case passes together with all 49 Swift tests. Instrumentation records 37/37 ChatModels lines and 36/36 regions covered, in evidence/chat/models-verification.json. Branch coverage and whole-product coverage are not inferred. The read-only review approved the correction but did not rerun tests; local tool output is the test evidence.

## Causal analysis and prevention

Why mismatch? Presence was used instead of truthiness. Why plausible? A valid database timestamp is normally nonempty. Why missed by the original positive test? It covered missing/valid timestamps and explicit false but not an empty string. Why relevant at a port boundary? Optional Swift strings and JavaScript Boolean have different semantics. How prevent recurrence? Use a source-derived table for null/missing/empty/nonempty/explicit-false cases, retaining the runtime RED and regression case. Fishbone axes: language semantics, wire nullability, legacy records and fixture boundary coverage.

No live browser records were created or changed. The earlier read-only empty browser screenshot is a baseline, not proof of equivalent populated native UI. Requirements for API, concurrent polling/stale results, actual guest/reference workflows, files, citations, SSE, approvals, Japanese IME and cloud egress remain open.
