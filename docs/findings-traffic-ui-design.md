# F5c native traffic evidence: requirements, design and tasks

## Complete scope and pinned baseline

Continue all21 workflow gates. The frozen e75ae371ad777ffd1eecdd28d2781a6519b05591 components finding-traffic-panel.tsx, traffic-picker-dialog.tsx and traffic-evidence-viewer.tsx are the authoritative interaction inventory. Preserve the original Docker reference separately; execute no agent command on macOS.

Required controls: evidence list with role, method/status, URL, capture time, note and evidence ID; inherited/legacy read-only feedback; add captured exchanges; edit four roles/note; adjacent move-up/down with exact versioned membership; remove binding; raw request/response tabs; initial and explicit further byte previews; binary feedback; full original-body download. The picker needs host/method/keyword filters, zero-based25-row paging, page/individual selection, exclusion of already-bound source IDs, selected count across pages, captured raw preview and explicit bind/cancel. Preserve loading/empty/error/reload, report-stale refresh after confirmed mutation, unknown-outcome recovery, current-owner confirmations and en/ja. Never execute, fetch or open a recorded URL just to display it.

Lazyweb `http request inspector` desktop search (2026-10-28) returned weak adjacent metadata: Postman Inc250787 GET parameters/navigation, Retool243659 request configuration/headers/body, HTTPie248764 documentation. No screenshots inspected or parity inferred. Retain ARTEX's list -> preview -> explicit action structure, readable monospace request/response and labeled controls. Actual keyboard, VoiceOver, screenshots and browser comparison remain pending manual unlock.

## Prerequisite audit and architecture

Existing FindingTrafficService/Store already cover bound summary/detail/byte pages and bind/edit/remove/order, with handoff/unknown ownership. They are not yet connected to FindingScreenModel or native detail controls. Missing prerequisites include typed `/api/traffic` candidate paging and `/api/traffic/exchange?id=` raw preview. Full-byte export is also absent: the existing attachment download path verifies a digest but does not save evidence bytes. A body preview must never substitute for download. Full-byte transport and explicit Save Panel/atomic export need their own bounded authenticated implementation and tests before download acceptance.

F5c1 adds finite candidate/preview contracts, directly supported by server.go getTraffic/getTrafficExchange, dto.go TrafficExchangeDTO and traffic.Page in the fixed source. Zero-based page, size1...500 (picker25), host/method/q are encoded as query values. IDs are opaque bounded UTF8, not finding numeric IDs; preserve bytes and distinguish canonically equivalent strings. Disabled capture with metadata can still have recorded history. Only the exact no-index shape (`enabled:false`, empty exchanges, no metadata) is unavailable; malformed/partial/null data must not become empty success. Metadata must echo requested page/size; no assumption that separate count/page SQL reads are transactionally identical. Raw preview req/resp stays opaque text, including blob pointers. Both reads are GET-only through authenticated finite JSON, cancellation before/after await, strict200 and4MiB bound; never return error bodies.

Next: owned picker state and preview generations; integrate traffic store into window/detail selection and dialogs; add full-byte export; then all native controls and actual disposable guest/browser comparisons. Picker selection uses UTF8 byte identities, keeps page selections explicit and prevents binding stale/already-bound rows. Mutations retain version/unknown gates and refresh report metadata only after confirmed receipts. Stop/reset must revoke all child activity without releasing unsettled writes. Parent filters, navigation and ordinary finding edits must share the busy gate.

## Ordered tasks and acceptance

1. Missing candidate API RED -> F5c1 DTO/service GREEN -> adversarial absent/null/disabled-history/Unicode/query/status/cancel/size tests -> review/full checks/build/CI.
2. Owned picker/preview and window integration RED -> state/controller GREEN -> dialogs and bilingual resources, stale/409/unknown/cancel tests.
3. Authenticated full-byte transport/export RED -> binary/large/hash/abort/atomic destination tests -> explicit save UI. Do not label a digest or preview as a saved file.
4. Native list/picker/editor/viewer/control inventory, offscreen locale/appearance checks; original source and recorded data preserved.
5. Actual nonempty isolated guest/reference API and persistence comparison, then unlocked native/browser/keyboard/VoiceOver/screenshot acceptance. All actual gates, F5 and complete-app acceptance remain open until evidence covers them.
