# Traffic state lifecycle investigation

## Reproduction/evidence
Initial fixture syntax and Observation multi-binding compile failures were corrected; the isolated missing-type RED011e54b is distinct from behavioral failures. The first13-case runtime failure was a test observer armed before the initial nil receipt assignment; moving it to stub dispatch made the intended arrival edge precise (1f5dd1f). Genuine negatives then exposed query retention across reset and unavailable-index recovery (8 assertions cbf26a7), and confirmed outcome escaping after synchronous busy-release departure (1 failure4b10089). These are local deterministic state/transport fixtures, not observed VM or visible UI failures.

## Root cause
5 Whys: private filters persisted because reset cleared reads/selections but not the query; query was treated as durable navigation state; auth reset and retained browsing state were insufficiently separated. Unavailable recovery passed because successful HTTP/decode/fresh flags were treated as adequate readback; the valid unavailable sentinel was not excluded. Retired-owner success escaped because the return value was computed before defer released the observed write gate; that release could synchronously stop/reset; validation preceded the final publication. All three needed semantic boundaries beyond successful asynchronous calls.

Fishbone: privacy—applied filters versus new session; availability—unavailable versus empty; concurrency—willSet reentry and deferred cleanup; scope—byte identity/immutable requests versus live drafts; testing—observer timing and compile RED versus actual behavior; acceptance—pure state fixtures versus real VM/UI.

## Repair/timeline
888736c initial compile failure → repaired missing-store contract011e54b → implementation23eb4d0 → corrected observer13GREEN1f5dd1f → query/unavailable REDcbf26a7 →15GREEN57c28fa → expanded18GREENd68b977 → busy-release RED4b10089 → post-cleanup ownership19GREEN738636c → cancellation20GREEN91f29fa → late detail21GREEN10227cd. Clear query on teardown, require available complete fresh recovery reads, and explicitly release the write gate before the final owner/session/activity/cancel check. Keep fallback cleanup for early exits, old-owner teardown guards, queued reset priority and immutable confirmation requests.

## Verification
21 state cases and all870 Swift cases (869pass/oneexistingAXskip) pass. TrafficStore357/358 and prepared TrafficService64/64 LLVM lines execute. Scope/code review found no remaining blocker. Full Python/build/signature and artifact receipts are recorded in traffic-state-verification/evidence. No actual destructive backend operation, network target, UI interaction or durable cross-window/process journal is claimed.

## Recurrence
Retain exact failed reset/unavailable/busy-release cases, partial host/settings failures, stale owner/revision, in-flight reset, no-dispatch stop, post-dispatch caller cancel, byte-distinct cross-page selections, and held detail/page responses. Do not replay unknown operations or infer rollback from HTTP failure. Fresh reads enable only explicit acknowledgment; success data is never returned to a departed owner after cleanup publication. Real VM/source/UI and full-product gates remain separate.
