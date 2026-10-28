# F5c2 owned captured-traffic picker

## Requirements

Implement the browser picker's state before wiring controls. Preserve25-row zero-based host/method/keyword paging and cross-page explicit selections. Already-bound source IDs are nonselectable; opaque IDs use UTF8 bytes. Reads never bind, and failed/stale reads cannot select an obsolete visible row. Raw preview identity includes the exact selected ID, query/view owner and parent evidence owner. Closing or parent selection change revokes queued dispatch and late replies. A bind uses an immutable selected snapshot; no auto retry or acknowledgement. Inherited/legacy targets stay read-only. Unsettled writes keep their gates across close/reopen.

## Design

CapturedTrafficPickerStore owns query, last-good catalog and preview FindingReadState, ordered byte selections, selected preview and a child submit ticket. Capture the parent FindingTrafficStore owner at construction/resume. Query changes invalidate catalog/preview and old control owners while preserving selections across pages. Only current fresh rows can be toggled or previewed; clearing selection is explicit and read-only. Bound source IDs derive from the parent's current summary and are excluded again at submission.

Add an internal parent apply overload with a child handoff validator, keeping the public API intact. Revalidate the child immediately before the parent's service handoff, because a synchronous parent busy notification can close the picker after permission was initially granted. Before handoff, departure sends nothing and is not uncertain. After handoff the parent owns its valid receipt or unknown outcome; a departed child must not publish success or clear a newer selection. Reads and acknowledgement never launch bind. Close revokes reads/selection and retains any child write ticket until terminal; resume does not release it.

This is state/controller work within the full UI plan, not a substitute for native controls or full-byte export. Use the pinned picker and the prior Lazyweb evidence recorded in findings-traffic-ui-design.md; no new product layout here. GitHub CI remains account-blocked by payment/spending-limit annotation40637957743. Do not repeat that run or change billing; local full checks remain required, remote CI is a pending gate.

## Tasks and acceptance

Missing store/child handoff RED -> cross-page/bound/Unicode/stale/reverse-read tests -> bind success/conflict/cancel/stop tests -> synchronous parent/child notification departure -> GREEN/review/full regression/coverage/signed build. Then window/detail/picker/viewer UI, full-byte export and actual nonempty guest/browser/keyboard/VoiceOver comparison. No paid provider or actual guest write is used in these state tests.
