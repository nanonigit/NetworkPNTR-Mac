# Findings UI lifecycle regressions

## 1. Observe and reproduce

F3.2 source inspection found asset-to-flat navigation did not restart polling after the one-shot asset loop returned. RED9d8ad0f executes the transition and fails the polling witness. Independent static review then found old inspector/close callbacks could dismiss a newer selection, a search timer could lose its query after page/mode changes, and old dialog getters could read newer drafts. RED73091e3 executes three shared-helper regressions with five failed assertions. These are controlled native component regressions, not real-window or guest observations.

## 2. Investigate

5 Whys: polling was lost because the view task had returned; no new task started because its identity did not follow mode; one-shot and repeating work shared one lifetime; callback bugs reused a view owner for detail/search/dialog lifetimes; initial tests did not interleave those distinct intents. Fishbone: lifecycle (one-shot vs repeating), ownership (view vs detail/session/dialog), scheduling (300ms debounce/cancel), tests (missing ABA and overlapping intent), UI (native closure retention). Timeline: missing-API RED -> five initial passing UI cases -> polling RED -> managed polling repair -> reviewer callback findings -> three callback RED cases -> scoped identity/search repair -> populated hosting, held-write and deep-tree tests -> re-review.

## 3. Repair

Manage view polling explicitly and await the old loop's terminal cleanup before acquiring its poll ticket. Stop cancels reads/polling and invalidates ownership, while later activation waits the retiring poll. Scope/page changes retain the same asset snapshot. Interactive reads coalesce through read/write gates; whole-table stats remain independent and explicit refresh includes stats.

All detail selections rotate a detail revision, including repeated/ABA selection. Inspector and Close validate captured view plus revision. A search intent uses session, exact draft bytes and control availability; it merges current filters after debounce, survives mode/page changes and resumes when a dialog gate closes. Replacement text or logout invalidates it. Old dialog text/severity getters return empty/keep and cannot write newer fields.

## 4. Verify

Controlled tests cover stale inspector and Close, ABA, page/mode/debounce, replacement/logout/dialog gates, stale draft/severity binding, held same-query tree with page/scope changes, held write and stop/reactivation/stats, all three populated views, four dialog kinds, inherited/legacy detail, stale/error notices, en/ja light/dark at900/1440 and4096deep forest. Offscreen hosts remain windowless and presentation creates no transport requests. See findings-ui-verification.md for final counts, coverage and normalized source fingerprints. Static re-review found no further blocker; actual visible layout, keyboard, VoiceOver, VM/reference parity remain open.

## 5. Prevent

Test each retained callback against its actual intent lifetime; view ownership alone does not identify detail or search intent. Every one-shot/repeating mode transition needs an active polling witness. Never call offscreen layout proof of actual UI, accessibility or browser acceptance. Preserve previous kernel/runtime failures and keep advanced workflows open.


## Hosted compiler compatibility follow-up

1. Observe: exact-head CI40437628991 fails compiling FindingFilterBar.body with type-check timeout, while local tests pass.
2. Investigate: one ViewBuilder combined six nested generic controls and task-label conditionals; different compiler resource limits exposed the oversized expression. 5 Whys leads from timeout -> large inference graph -> one builder boundary -> insufficient hosted-toolchain evidence -> local-only compile acceptance. Fishbone adds compiler/environment and expression structure; timeline is local GREEN -> CI RED -> split controls -> local rerun -> exact-head CI.
3. Repair: split search/severity/status/sort/class/task builders, explicitly type the UTF8 class binding and simplify the task-title fallback. Keep layout, identity and mutation guards unchanged.
4. Verify: static re-review found no behavioral change; full578 local Swift rerun passes with one existing skip. Signed rebuild and fresh-head hosted CI remain separately verified.
5. Prevent: keep generic builders small and require hosted-compiler CI for the exact published head; never treat local compilation as cross-toolchain proof.
