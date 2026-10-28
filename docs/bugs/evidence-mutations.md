# Evidence mutation integration: timestamp and retained-store ownership

## 1. Reproduction

Timestamp REDf72bcab failed three assertions over Unix epochs0,1,-1,1792663200: native display divided seconds by1000. Frozen traffic/traffic.go writes now.Unix(); the browser multiplies seconds by1000 only for JavaScript's millisecond Date. GREENbda51bd passed23 workspace tests.

The mutation/action missing-contract REDb9dd4f6 preceded4eade81(31 tests). View/render-version/cancellation missing contracts RED5f5542c preceded6b8d4fb(75 related tests). These compile-time missing API contracts are not runtime failure claims. Subsequent actual REDa81c4d0 failed nine assertions in14 action cases: repeated stop from sheet A cleared replacement B's shared store; after reset and a new-session write, A's late submission cleanup stopped the new owner and marked it uncertain.

## 2. Evidence

The two ownership regressions use the same retained store and held write continuations, including two distinct sessions/writes. They inspect active/owner/read/unknown state and terminal results rather than just method construction. Timestamp comparison uses numeric epoch equality and source semantics, not a rendered synthetic date. The first implementation test attempt also exposed invalid test setup (inherited record without source_task_id) and Foundation JSONSerialization consuming a leading BOM in the request-note assertion; fixtures now obey the record contract and assert note bytes using BackendJSONCoding. Those fixture repairs were not product-data normalization.

## 3. Cause analysis

5 Whys: capture time was displayed incorrectly because native reused a millisecond conversion; JavaScript and Foundation Date units were conflated; synthetic fixtures also used milliseconds; no numeric browser/source contract test existed. Root cause: unspecified timestamp unit at the presentation boundary.

For teardown: A could stop B because cleanup acted on a retained mutable store; the store had outlived the presentation; stop carried no owner capability; late command cleanup assumed its original store was still current; tests initially covered ordinary close/reopen uncertainty but not delayed disappearance or session replacement. Root cause: changing resource lifetime without binding destruction to the same ownership model as commands.

Fishbone: timestamp units and fixtures; shared-store lifetime; late continuation cleanup; session reset; missing destructive-operation ownership. Timeline: f72bcab/bda51bd ->b9dd4f6/4eade81 ->5f5542c/6b8d4fb ->a81c4d0/26c540b(77 related GREEN).

## 4. Repair

Use Unix seconds directly and document the DTO unit. Retain the window's evidence store, unresolved write and immutable recovery target/context across sheet closures; only logout resets the session. Capture each workspace's store owner. Scoped stop returns its own captured replacement token; late scrub can only act on that stopped owner, never a newer selection/session. UI/dialog commands also require the captured workspace/store/version/membership. Preserve opaque note text and unknown roles, require explicit role choice, block replay, and refresh parent metadata only after confirmed owner-matching receipts.

## 5. Verification and recurrence prevention

Keep the epoch, stale-render/version/membership, pre/post-dispatch stop/cancel, held response, replacement-sheet/session, note byte, inherited, unknown acknowledgment and confirmed metadata tests. The14 action plus23 workspace cases join existing finding/core regressions (77 related cases). See findings-traffic-mutations-verification.md and Japanese counterpart for the full local test/build checkpoint. Actual nonempty guest/reference mutation/persistence, captured picker and unlocked UI/accessibility remain open; this is not complete-app acceptance.
