# Chat error localization — L4b

## Reproduce and gather

L4a provided an explicit-language presenter, but Chat stores still captured rendered Japanese strings. An error already on screen could not follow the language picker. The source proves the missing presentation boundary; no live reproduction is claimed in this checkpoint.

`96eae3e` captures intended compile-time RED for missing typed store values. The test fixture was corrected to the existing pickFiles API and uploads/ path contract before the authoritative RED run; initial setup mistakes are not product failures. `0796897` passes the same3tests. Tests exercise a real ChatService through scripted transport: failed send restores literal mixed-language draft and card, English/Japanese lookup does not issue a request or change selection; list/history/workspace/upload errors resolve by locale; unknown mention failure discards secrets; failed user-body load preserves literal summary.

## Analyze

5 Whys: visible error cannot switch → store holds rendered text → rendering occurs in catch → locale is unavailable there → error identity was not retained. Fishbone: value identity, observable ownership, per-conversation dictionaries, generation/cancellation guards, locale-dependent view rendering, raw backend data safety. Timeline: inspect current source → Lazyweb adjacent evidence → requirements/design/tasks → fixture correction → intended RED → safe typed storage and view resolution → GREEN → reviewer/full regression/coverage → signed build; actual UI comparison deferred.

## Repair

AppErrorMessage retains only closed BackendAPIError/ChatUploadBodyError values or a catalog key. Unknown errors are reduced immediately to a safe fallback, without retaining descriptions or paths. Chat list/history/mutation/workspace/upload/mention/body failures now store this value. The selected view locale resolves text at render time, including the detail sheet. Existing Japanese computed String properties remain for diagnostics/old callers. No language-based view identity or new task is introduced. Previous generation/lifetime/cancellation/owner checks and per-conversation failure dictionaries are preserved. Four static fallback messages join the bilingual catalog. Source layout and retry behavior follow the fixed browser; Lazyweb search `chat error retry message` returned weak adjacent DoorDash metadata(similarity.385), not inspected visual evidence or parity proof.

## Verify and prevent

Full246Swift cases:245pass/one existing AXskip;52Python pass. Safe-value helper AppErrorMessage lines13/13 and regions11/11. Final signed app build and strict signature pass; all33error catalog entries per language match bundled resources. Read-only review approved store ownership and locale-only presentation. Tests and portable-catalog drift checks protect this boundary.

The native UI tool reported the Mac locked and automatic unlock unavailable. The user chose to unlock later. No new VM/browser fixture was started, no native screenshot was captured, and no native/browser failed-send switching result is claimed. Actual error switching with draft/card/caret/selection preservation remains a required gate after unlock. Prior L3 screenshots only prove their earlier, error-free switching scope. Authentication/LLM/Dashboard/runtime errors, backend language synchronization, default-title provenance, IME/VoiceOver, remaining screens and all21 feature acceptance remain open.
