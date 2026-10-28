# LLM ownership and recovery verification

The service/store and window wiring now retain uncertain writes across same-session navigation, block repeats, and offer explicit recovery after a full reload. This is a software checkpoint of the complete-app goal, not full workflow acceptance.

## Evidence

- Initial missing-API REDdb2de38 ->28 focused GREENc16fd45.
- Expanded RED6b3a35c exposed two stale-review assertion failures and recursive-stop signal11; localization RED3c84608 exposed the missing recovery keys. GREEN89f6728 passes36 focused tests.
- Review-driven resume RED3e903fb: two tests/three failed assertions. GREEN2088822 passes38.
- Window-ownership missing-type RED4210528 ->41 focused GREENfb106b1. Offscreen rendering525c9c8 brings total focused checks to42 (38 Core,4 Mac).
- Full Swift:680 cases,679 pass, one existing explicit external-AX skip, zero failures.
- Python guest/tooling:123 pass.
- Full-suite line coverage: LLMService131/133 (98.50%), LLMStore172/173 (99.42%), LLMWorkspace13/13 (100%), LLMRecoveryView207/210 (98.57%). Coverage of view body construction is not proof of external interaction.
- 112 reviewed LLM UI entries match both locales; four new recovery keys have only en/ja translations. Offscreen tests preserve literal FEFF/NFD and custom Chinese/Korean names. LLM-owned Swift sources contain no Hangul literals. Provider-generated diagnostics and real rendered screens still need the broader localization audit.
- Localization export and fixed baseline inventory pass:21 navigation features,27 routes,243 handlers. Native workflow parity remains pending.
- Independent read-only core, UI, lifecycle correction, coordinator and rendering reviews: no remaining reported blocker in this scope. Resume finding was reproduced and repaired before this result.

## Boundaries

All requests used synthetic finite replies; no real keys, cloud probes, guest writes or agent commands. The recovery panel was constructed offscreen in English/Japanese, light/dark and440/630/900 widths, with empty/populated/current/unreviewed/inactive states. Rendering never reads, writes or acknowledges. This does not prove real sheet fit, native keyboard/VoiceOver, screenshots or browser parity. External comparison resumes after the user's manual unlock. Editor/probe task ownership, uncertainty across app termination, native cloud egress, actual guest/browser comparison, F5 and all21 feature gates, kernel reliability and release/install gates remain open.

Signed build-only and strict signature verification pass. This build was not launched for external acceptance.

## CI fixture correction

[Run40610980734](https://github.com/nanonigit/artex-mac/actions/runs/40610980734) failed three assertions in the confirmed-save/follow-up-refresh test. The fixture used an equal-value `noticeKey = nil` Observation notification to select a hold point; the CI compiler delivered that notification, holding POST instead of GET. Production was unchanged. The corrected fixture explicitly holds the first GET and asserts the observed sequence is POST,GET before departure. Other dedicated Observation regressions remain. This strengthens phase evidence rather than relaxing outcome assertions. Independent review confirms the correction; subsequent exact-head CI must be checked separately.
