# Native evidence sheet lifecycle regressions

## 1. Reproduction

The initial missing-contract RED a4b28fa was followed by nine workspace/file tests at666bb50. Missing view/presenter contracts at7e45408 then passed11 cases at6029c49. These initial RED stages were compile-time missing contracts, not runtime failures.

Additional adversarial tests exposed actual bugs: a retained dismissal for sheet A closed replacement B; a verified receipt for an empty body could publish where the selected response expected three bytes; synchronous departure during busy publication opened the chooser afterward; and stop callbacks reentered cleanup. The12-case stale-dismiss run failed two assertions. The17-case run failed six assertions across stale dismissal and mismatched receipt. The20-case RED5989dd7 showed further reentry/chooser failures and terminated with signal11 during preview-departure publication. Parent publication RED9628164 independently terminated with signal11. Later REDf0f71a9 ran22 cases and failed two assertions: cancellation before task assignment still opened a chooser, and the retained binding getter exposed B.

## 2. Evidence

Tests use fixed fake JSON and real exclusive temporary files; no model keys or recorded external URLs are fetched. Held continuations release late reads/receipts; synchronous Observation callbacks test willSet departure. Reentry counters are bounded where possible. The signal11 verdicts are failed test-process outcomes, never passing acceptance. Failed local run logs stay private. No user document was used as a fixture.

## 3. Cause analysis

5 Whys: presentation used the current identity instead of the captured identity; observed property writes allowed departure before the write completed; cleanup updated those same properties without a transition/reentry boundary; export cancellation relied only on an assigned Task; tests had covered ordinary asynchronous departure before synchronous observer callbacks. Root cause: owner validation at entry was treated as sufficient across synchronous publication and task acquisition. A separate integrity gap trusted the export closure's receipt without comparing it to the UI's selected immutable manifest.

Fishbone: presentation identity; Observation willSet ordering; parent-versus-child lifecycle; task acquisition/cancellation; staged-file receipt identity; missing synchronous negatives. Timeline: a4b28fa/666bb50 ->7e45408/6029c49 ->5989dd7/59063fc(20 GREEN) ->9628164/5ba58f6(50 related GREEN) ->f0f71a9/98aa36e(51 related GREEN).

## 4. Repair

Capture the presentation UUID for both binding getter/setter. Queue departure during an entire synchronous publication, then drain cleanup; reject new work during transitions and guard stop/cancel reentry. Validate ownership before the chooser, after destination choice, after staging and immediately before file commit. Latch cancellation even before the Task exists. Match receipt status/size/SHA-256 to the immutable body manifest. Parent creation checks its lifecycle after publication and revokes a workspace restored by willSet; parent close/stop/reset are guarded against reentry. The panel belongs to its actual sheet window and is cancelled on detachment.

## 5. Verification and recurrence prevention

Keep22 workspace tests plus existing finding model/view regressions (51 related cases). They include held reads, byte offsets independent of rendered text, raw FEFF/NFD/CJK data, binary feedback, inherited/legacy behavior, wrong/stale owners, actual save, existing-file protection, mismatched receipt, late receipt cleanup, safe errors, busy cancellation and parent/child reentry. Offscreen en/ja light/dark rendering is software evidence only. See findings-traffic-ui-verification.md for the full-suite/build/publication checkpoint and remaining real UI, preview/API, picker/mutation/persistence and release gates.
