# Findings screen coordinator verification — F3.1

Implemented captured edit/status/delete/uncertainty dialogs, safe preference restoration and in-memory unsent drafts. This is the coordinator before native controls. RootView is not connected yet; Findings remains pending. No app launch, live ARTEX write, VM boot or visual acceptance was performed.

- Missing coordinator API RED: cd266a7. Initial 11 coordinator tests passed, then review found unsent draft loss on stop. Executed regression RED81db173 failed three field assertions; repair f503a45 passes all13 tests. See bugs/findings-screen-draft.md for observation, investigation, repair, verification and recurrence prevention.
- Full local Swift:563 total,562 pass,1 existing external-AX skip; Python86 pass. Coverage: FindingScreenModel106/115 lines (92.17%), FindingScreenPreferences23/23 (100%). Read-only re-review found no remaining blocker in this scope.
- Build-only signed app, strict signature, localization export, shell syntax and frozen source inventory checks pass. No npm/pip application dependency manifests are present; no JS/Python application dependency or audit surface was added.
- Controlled tests cover literal Unicode edit wire, separate status-only PATCH, old view rejection, all post-dispatch failures remaining unknown, no replay, captured acknowledgement episode, stop/reset during held writes, inherited/unavailable targets, preference exclusion/bounds/fallback, wrong dialog ID, unsent draft retention/cancel/reset, finding identity and submitted-edit exclusion.

The pinned browser source persists view/severity/status/vulnclass/task/sort and excludes search/cursors. Native versioned storage intentionally validates the whole preference object and canonical task ID rather than partially accepting corrupt fields. Name/class/severity editing excludes status; status confirmation sends only status, matching the browser's separate controls. This is source inspection and controlled transport evidence, not rendered browser parity. No stored user/history content is translated or rewritten.

Normalized evidence and tested file SHA256 values: evidence/findings/f3-screen-verification.json. All prior runtime fault evidence remains; no kernel candidate is promoted. See findings-screen-design.md for Lazyweb metadata limits and the fetched table practice.

Next: F3.2 implement en/ja native list/group/tree/filter/pager/detail/edit controls, stable raw-byte asset identity, per-window authenticated retention and gate-aware read scheduling. Add presentation/binding/offscreen tests, then perform actual native/browser keyboard/visual/VoiceOver checks after manual unlock. F4 actual isolated VM/reference changes and F5 export/traffic/report/lineage/retest/deepen remain required. Full21/cloud/clean-Mac/release/reliability gates remain open.


Later checkpoint: F3.2 now connects native controls and changes Findings to in_progress. See findings-ui-verification.md for current evidence and open gates; the F3.1 results above remain historical.
