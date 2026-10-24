# Authentication/settings/dashboard error migration — L4c

## 1. Reproduce / 2. Gather

Current source showed AuthenticationSession/LLMStore/DashboardLoadState storing eagerly rendered Japanese errors. L4b only covered Chat. LLM success notices were also rendered strings. This is source evidence of an explicit-language presentation gap, not a new live UI reproduction.

`a229ee3` is intended compile-time RED for typed failure/notice values. `7b6c8c5` is GREEN for four store/service tests. A local mixed-type coalescing compile error in LLMSettingsView was found by the compiler and reviewer, fixed before GREEN to `(localError ?? store.failure)?.text(language: language)`; it is not an upstream product defect or an additional product RED. `4cbb734` adds three regression cases; all seven focused cases pass. These use real services with scripted transport/in-memory vault, no live credentials or cloud calls.

## 3. Analyze

5 Whys: errors/notices remain Japanese → state holds rendered Strings → service/store catch renders immediately → current view locale is unavailable there → ports lacked a shared safe identity boundary. Fishbone: authentication/vault phase order; mutation confirmation versus reload; cached dashboard data/timestamps; polling/cancellation; local sheet state; raw backend messages; catalog resources. Timeline: source audit and requirements/design/tasks → weak adjacent Lazyweb metadata → intended RED → typed values/view resolution → compile repair/GREEN → reviewer → full run → coverage-driven action/poll regression tests → final full run and signed resources.

## 4. Repair

AuthenticationSession and LLMStore store safe AppErrorMessage values with Japanese computed String compatibility. DashboardLoadState stores a safe failure while preserving last-good value/timestamp. Error views resolve the live locale in authentication, LLM settings/editor/rotation, and dashboard. Local editor/terms-load errors also retain safe typed identity. Six confirmed LLM notices are catalog keys, so the successful mutation notice survives a subsequent refresh failure. Unknown errors discard raw descriptions immediately; numeric known failures retain their safe diagnostics.

No task identity, authentication/vault ordering, password/API-key storage, field binding, agreement state, polling interval or cancellation/generation semantics was changed. Existing backend-provided pool diagnostics and model replies remain unchanged and must be audited with provenance separately. Lazyweb query `settings inline validation error` returned weak adjacent Gopuff captcha metadata(similarity.356); it was not visually inspected or treated as UI parity evidence. Fixed browser layout/error placement remains the reference.

## 5. Verification and recurrence prevention

Final test counts and measured Core-file coverage are recorded in `evidence/localization/screen-error-verification.json` and `screen-error-coverage.json`. Tests cover authentication validation/phase/no side effects, unknown-error sanitization, confirmed save with failed refresh, all six LLM success notices, rejected mutation without false success, cached dashboard data/timestamp retention, all three poll failure groups, no new requests on locale resolution, and cancellation stopping the polling task. Existing regression suites cover authentication/upload/session behavior and stale generation replies. Final signed bundle error/notice values are checked against the single catalog; exporter drift check and strict signature verification pass.

This checkpoint does not claim external native/browser switching, surrounding screen labels, English terms display/read gating, actual IME/VoiceOver, runtime errors, backend language synchronization/default-title provenance, remaining18screens, or all21feature acceptance. User deferred unlocking the Mac in the preceding turn; no new UI control attempt or runtime fixture was started here. Actual comparison remains required after unlock. The full goal stays active.
