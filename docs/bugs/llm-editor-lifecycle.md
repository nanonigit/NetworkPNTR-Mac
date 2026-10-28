# LLM editor lifecycle: five-stage regression record

## 1. Identify and reproduce

The view launched unretained Fetch/Test/Save tasks; disappearance only cleared input fields. Missing-owner RED1700475 specified six cases. GREEN85bc270 passed six. Expanded RED19dd23b completed15 cases with six assertion failures: queued parent departure, parent stop/resume queued and late probes, and a draft setter restoring a key after synchronous close. A confirmed-key-scrub/proxy counterpart is retained too. A temporary mechanical argument-label error in view wiring was fixed before the behavioral RED; it is not counted as behavior evidence.

## 2. Evidence and timeline

Synthetic finite transports hold explicit requests, then close, edit or rotate the parent activity before releasing valid or error replies. Queued closure sends zero requests; handed-off closure retains its gate and ignores the reply. Save cancellation is routed through the existing store, preserving unknown-result recovery.Corrected3110030 passes57 LLM checks; the sole-draft-owner/offscreen refactor333302b passes59 (38Core/21Mac). No real keys, provider calls, guest writes or agent commands.

## 3. Root cause

5 Whys: late callbacks changed editor state because Tasks captured the view without retained cancellation handles; outputs lacked activity/draft ownership; parent availability was not generation-bound; clearing only visible inputs did not invalidate captured work; existing tests covered service contracts, not sheet lifetime. Fishbone: ownership—unstructured tasks, identity—draft and parent epochs absent, notification—willSet callbacks can close before setter commit, secrets—outer setter can write a key after cleanup, tests—no adversarial sheet departure. Timeline: publish busy -> depart/edit -> request/reply continues -> outdated output or dismissal; and draft willSet -> close scrubs -> original setter commits key -> inactive model retains it.

## 4. Repair

LLMEditorModel owns draft, validations, one ticket and cancellable task. Ticket captures editor activity, draft revision and the parent's read-only activityID; all dispatch/results require a match. Draft edits synchronously invalidate and cancel work; inactive setters scrub credentials after the original assignment. Close changes lifecycle before observable cleanup; old operations keep their local gate until terminal. Confirmed-save cleanup does not revoke its own receipt, but close/edit prevents dismissal. The view retains only model and masked hint, preserving one live draft owner. Explicit Close cancels before dismiss, disappearance cancels, save disables interactive dismissal. No automatic retries or calls.

## 5. Verification and recurrence prevention

Keep pre-start, post-handoff, parent stop/resume, exact FEFF/NFD/CJK edits, receipt/key scrubbing, synchronous busy/result/draft-close callbacks, pre-cancelled caller and validation cases. Read-only reviews found credential restoration, reproduced it, then verified correction. Offscreen construction exercises formats/new/edit/locales/appearance/candidates/test/error without implicit requests. Visible layout, model-picker interaction, native keyboard/VoiceOver, actual browser/guest/provider comparison and process-restart uncertainty remain separate gates.
