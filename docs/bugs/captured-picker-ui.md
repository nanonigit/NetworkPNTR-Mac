# Captured picker UI regressions

## 1. Reproduction

Missing picker contracts RED9dc8489 preceded ae53eb2 with10 passing state cases. Missing native view contracts RED5505d8b preceded the view implementation. The first14-case runtime run then failed one assertion: restarting an unchanged filter task reset page1 to0. Added synchronous observer cases reproduced a direct stop restoring a cleared host draft, followed by a child-close precondition failure and test process signal5 atcd9c347. These are actual failed runtime outcomes, distinct from missing-contract compile errors.

## 2. Evidence

Tests use fixed non-network fixtures, real core stores, byte-distinct Unicode IDs, held reads/writes and synchronous Observation callbacks. The page test compares the applied cursor. The draft test inspects inactive model contents, not only a binding that hides them. The child-close test calls the captured presentation during the actual draft publication boundary. A crashed test process is never accepted as a completed run. Raw logs remain private; no real captured traffic, keys or server state is committed.

## 3. Cause analysis

5 Whys: page position was lost because every filter task built page0; view task restart and a changed filter were treated identically; query ownership and draft identity had been separated without preserving unchanged query state; only changed-filter reset was initially tested. Root cause: conflating restart with a new filter.

For close/drafts: input publication allowed synchronous departure; close entered the workspace's non-nestable transition; direct picker stop cleared a draft before its outer setter committed; cleanup was assumed final before publication ended; initial tests covered workspace departure but not direct child stop/close. Root cause: the child needed the same accepted-intent queue and post-publication cleanup boundary as its parent.

Fishbone: query restart versus edit; synchronous observation; nested child/parent transitions; raw draft lifetime; pre-busy cancellation; missing negative fixtures. Timeline:9dc8489/ae53eb2 ->5505d8b ->cd9c347(runtime page/draft/crash) ->4a313dd(100 related GREEN) ->additional accepted-prebusy-close, timestamp and preview/loading/submit render cases.

## 4. Repair

Start from the current query and reset page only if byte-based filter drafts changed. Keep cancelled/stale tickets inert. Queue an accepted close using its captured picker UUID; outer workspace stop wins. A close accepted before busy publication revokes the just-acquired submission before dispatch. Scrub only the departed picker's own drafts after publication; repeat stop remains reentry guarded and never stops another picker's shared evidence store. Reuse existing scoped evidence teardown and uncertain-write retention.

## 5. Verification and recurrence prevention

20 picker cases now cover selection/filter/page/raw preview/bind/unknown/owner/reentry and en/ja light/dark rendering, including empty, unavailable, loading, safe errors and pending writes. Keep the exact page/draft/close negatives plus prior core picker and evidence lifecycle regressions. Full824 Swift cases and155 Python cases are recorded in captured-picker-ui-verification.md with explicit real guest/reference/persistence/UI gates still pending. Offscreen construction and fixture request success do not prove actual native/browser workflow parity.
