# LLM editor lifecycle

## Requirements

The profile sheet owns model-list, connection-test and save tasks. Closing must request cancellation before queued dispatch where possible, clear transient API-key/proxy fields and reject every late result/error/dismissal. Dispatched provider requests may already have run; cancellation is not rollback. Draft changes revoke old candidates, test results and save receipts, including byte-different Unicode edits. An unsettled operation keeps its local gate until terminal even if the sheet is reopened. Saves retain the existing LLMStore handoff/uncertainty gate. Do not add automatic cloud requests, retries, secret persistence or host agent commands. Keep all browser fields and en/ja controls.

## Design and reference

Extract a MainActor observable LLMEditorModel owning draft, validation markers, transient output and a task handle. One operation ticket contains editor activity, draft revision and operation kind, never a second persisted credential store. Synchronous acquisition revalidation prevents Observation callbacks from closing a sheet before an already queued dispatch. Draft mutation advances a private revision synchronously; explicit credential scrubbing after a confirmed save preserves its receipt. Close changes activity before observable cleanup and is idempotent/reentry safe. Activate does not release an unsettled old ticket. Every completion and cleanup checks its owner; a saved receipt dismisses only the current active sheet. The SwiftUI editor binds to the model and cancels it on disappearance. Interactive dismissal is disabled during a save; forced departure still cancels and LLMStore tracks dispatched uncertainty.

Primary source is pinned e75ae371ad777ffd1eecdd28d2781a6519b05591 LLM page and existing native field inventory. Lazyweb `api connection test` desktop search (2026-10-28) returned weak adjacent metadata: Postman Inc250775 suites/validation, Postman245868 request flow, Uptrends233805. No screenshot was inspected and these are not acceptance evidence. Preserve ARTEX's explicit Fetch/Test/Save actions, busy feedback and labeled fields; no visual redesign or new UI strings.

## Tasks and acceptance

1. RED for missing editor owner: pre-start close, held late results, byte-exact draft invalidation, serialization, current success/error, saved receipt and secret cleanup.
2. Implement task/ticket lifecycle and validation; test synchronous notification departure, close/reopen, stale save and full-store unknown recovery integration.
3. Wire existing controls, disappearance and dismissal. Offscreen render both locales without reads/writes; preserve custom CJK/FEFF/NFD values.
4. Independent review, focused/full regression and coverage, signed build, exact-head CI. External click/keyboard/VoiceOver and browser screenshot comparison remain pending manual unlock; offline fixtures do not establish actual provider/guest acceptance. Durable uncertainty across process termination and remaining full-product gates stay open.
