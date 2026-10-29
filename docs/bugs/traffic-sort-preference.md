# Traffic sort restoration lifecycle investigation

## Evidence
02441cf intentionally fails compilation because preferences injection is absent.0aee4c0 implements the contract and reproduces one runtime assertion failure in9 cases: resetting from restored-query publication scrubs model/query and preserves the original stored bytes, but begin still returns a retired lease.454d398 adds the post-restoration ownership check and all9 cases pass. Read-only review independently found the same boundary and verified the fix without running tests or changing files.

## Analysis
Five Whys: begin returned the proposed lease after a failed restore; false meant both a temporary old-write gate and ownership loss; begin checked ownership only before the new synchronous restore operation; restore can publish a query and trigger Observation reset; the post-publication lifetime boundary was missing. Recheck ownership before polling/return while retaining a valid pending presentation behind an outstanding write. Do not fix this by rejecting all deferred restores: the held-write case must still restore and refresh after settlement.

Fishbone: lifecycle—before/after restored-query publication; gates—temporary write versus retired lease; storage—accepted canonical field/direction versus private query; concurrency—queued reset priority and notification reentry; testing—disposable preferences and injected transport versus real root/UI/OS permissions.

## Repair and recurrence
Only typed whitelist sort fields/directions are written under a separate native key. Restoration canonicalizes to those two keys after accepted configure; controls save only accepted sort operations. Stop/reset clears pending hydration and raw transient state, not the saved nonprivate choice. Keep valid-pair/invalid/oversized/unknown-field, no-construction-write, privacy/reopen, blocked/stale, stop-during-save, reset-during-restore and held-write regressions. The held-write test checks first-read sort, one DELETE and retained explicit-ack uncertainty.

Production standard-domain permissions/root activation/real browser/native/keyboard/AX are not proved by disposable suites. No live provider request, VM mutation, real user preferences modification or automatic retry/ack is introduced by these tests. See traffic-sort-preference-verification en/ja for final finite checks and remaining whole-goal gates.
