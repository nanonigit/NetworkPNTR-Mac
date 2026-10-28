# LLM editor lifecycle verification

The sheet now owns Fetch/Test/Save through one MainActor model, revokes work on close or draft change, captures parent activity and prevents stale dismissal. This is a software checkpoint of the complete application goal.

- Missing-owner RED1700475 -> six tests GREEN85bc270.
- Expanded behavioral RED19dd23b:15 cases, six assertion failures covering parent departure/reentry and key restoration after a synchronous close. Corrected3110030 passes57 LLM-focused tests.
- Sole-draft-owner and offscreen refactor333302b passes59 focused tests (38 Core/21 Mac).17 new cases cover15 owner tests and two rendering tests.
- Full Swift:697 cases,696 pass, one existing explicit external-AX skip, zero failures.
- Python guest/tooling suite:123 pass.
- Full-suite line coverage: LLMEditorModel120/122 (98.36%), LLMProfileEditor391/430 (90.93%), LLMStore173/174 (99.43%). View construction coverage does not prove mouse, keyboard or accessibility acceptance.
- Localization export and pinned source inventory pass:21 navigation features,27 routes,243 handlers; workflow parity remains pending. No owned UI text was added. Existing112-entry LLM en/ja matrix still passes, and arbitrary Chinese/Korean, FEFF and NFD input stays byte-preserved.
- Independent read-only model/UI and rendering reviews found credential restoration, which was reproduced and repaired; no unresolved reported blocker remains in this scope.

Tests use synthetic finite replies and literal dummy keys only. No real API-key import, cloud call, guest mutation or agent command occurred. Pre-start close and parent activity changes cause zero dispatch; uncooperative post-handoff replies settle without populating a departed draft. Confirmed saves scrub their draft key, while departed dispatched saves preserve LLMStore uncertainty. The view no longer retains an extra immutable draft copy. Rendering covers all formats, create/edit, both languages, light/dark, candidates, connection result and error states without implicit requests.

Actual native/browser click/keyboard/screenshot/VoiceOver, model-picker behavior and sheet fit remain pending manual unlock. Actual provider/guest comparison, durable uncertainty across app termination, F5, all21 feature acceptance, kernel reliability and clean-Mac/release gates remain open. Cancellation after provider handoff cannot prove a request was not executed or charged.

Signed build-only and strict code-signature verification pass. This build was not launched for external acceptance.
