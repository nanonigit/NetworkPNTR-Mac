# Findings screen draft lifetime

## 1. Observe and reproduce

Read-only F3.1 review found `stop -> clearDialog` discarded unsent name/class/severity edits, contrary to retained sidebar drafts. Reproduce with beginEdit, literal Unicode edits, stop, reopen the same finding. No actual UI or guest mutation is involved.

## 2. Investigate

5 Whys: draft lost because stop cleared fields; fields cleared because dialog cleanup owned inputs; cleanup shared because confirmation and draft lifetimes were coupled; coupled because initial coordinator modeled one dialog lifetime; missed because stop coverage asserted only search retention. Fishbone: state ownership (dialog/draft coupling), lifecycle (stop vs logout), tests (search-only witness), UX contract (retained drafts), transport (not involved). Timeline: initial missing-API RED -> 11 passing coordinator tests -> reviewer finding -> targeted edited-draft regression RED -> separate retained draft GREEN.

## 3. Repair

Keep only an unsent, non-uncertain edit snapshot in window memory, keyed by captured authentication session and standalone finding ID. Stop still invalidates the confirmation owner. Reopening explicitly captures a fresh confirmation; it may recover only the matching draft. Cancel and logout discard it; submitted/uncertain edits never become replayable drafts. No disk persistence or automatic write.

## 4. Verify

The focused regression checks literal FEFF/NFD/CJK fields and severity, rejection of old confirmation ID, fresh view owner, explicit Cancel and authentication reset. Extend with different finding identity and submitted-write exclusion. Full suites and read-only re-review follow; see findings-screen-verification.md for executed results.

## 5. Prevent

Keep draft and authorization lifetimes separate. New sidebar/locale owners must test edited fields, old confirmation rejection, identity/session boundaries and pending-write gates. Actual UI/browser/keyboard/AX validation remains pending after manual unlock.
