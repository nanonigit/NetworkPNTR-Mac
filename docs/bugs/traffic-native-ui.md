# Native Traffic control boundary investigation

## Evidence and reproduction
0b39c47 is an intentional missing-view/helper compile RED;710ce7a passes seven initial UI/binding/offscreen cases. Read-only review identified stale pager ownership and a pending-input acknowledgment gap.2438963 reproduces three acknowledgment assertions and one actual multiline-Host mismatch. c752cb9 adds the scoped pager API compile contract and22 synthetic expected packets produced by executing the pinned browser requestWithHost function with only TypeScript annotations removed.5ca6471 passes nine cases. This function oracle is not actual browser UI acceptance.

The first full suite then exposed one outdated CoreTests expectation that every feature beyond the prior five was pending; Traffic now has real controls. Keep explicit traffic=in_progress and all other pending assertions without altering21/27/243 inventories.1360bf5 reproduces a retained dialog context after auth reset (one assertion);8df1796 reproduces queued deletion behind an open preview (four assertions), including inability to close the preview once the second modal owns controls.361c471 repairs those boundaries and passes the full916 cases (915pass/oneexistingAXskip). Final picker-tag coverage is recorded separately in the finite receipt.

## Root cause
Five Whys: pager closures carried presentation identity but omitted query identity, so a delayed old action could address a fresh query; ownership rules were enforced inconsistently across UI controls. Acknowledgment relied on a disabled button rather than the model's pending-input policy; delayed callbacks can bypass presentation state. Capture query owners and enforce eligibility in model methods.

Host completion split the packet into lines before scanning, but the browser regex permits ECMAScript whitespace—including newlines—between Host and colon. Scan scalar positions at browser multiline starts, retaining exact whitespace/case semantics, and leave the raw DTO unchanged.

The confirmation view stored its frozen raw scope directly, independently of the current model; reset cleared the model but not a retained view value. Derive context by current lease and operation ID. Preview visibility was not a model interaction gate, so a queued background deletion could create two modal states. Gate interactive controls on preview state while separately allowing read refresh and scoped preview dismissal.

Fishbone: identity—query owner/lease/preview revision/dialog ID; UI—disabled appearance versus actual eligibility; privacy—stored view context versus current context; protocol—ECMAScript scalar/newline semantics; lifecycle—auth reset and delayed callbacks; testing—offscreen rendering/binding calls/function oracle versus visible browser and real backend effects.

## Repair and recurrence
Keep exact pending-ack, old-query pager/reset, multiline Host, retained-dialog-reset, held-write-discard and preview/deletion regressions. The held write retains its progress context until outcome or reset, forbids cancel/replay, and records generic uncertainty after departure. Clipboard copying rechecks current packet/freshness before changing the clipboard. Picker tests cover valid/invalid/stale tags and all browser page sizes/status buckets. Reuse the fixed22-case Host oracle, byte identities and literal CJK/FEFF/NFD cases; do not translate raw packets or replace data markers.

Read-only reviews found no remaining concrete blocker in the repaired deltas. They are not real UI/VM acceptance. Root activation, actual modal/focus/keyboard/VoiceOver/multiwindow and source/reference effects remain separate gates, as do flow binding, original blobs and sort persistence. See traffic-native-ui-verification and its Japanese counterpart for final counts and per-file coverage gaps.
