# Shared production body model: actual VM verification

Status: production-model-to-VM gate passed using an automated chooser. Native window/panel/input/VoiceOver acceptance and full app completion remain open. [Receipt](../evidence/traffic/production-model-vm-verification.json), [design](traffic-body-model-vm-design.md).

## Shared implementation

88036d3 defines a VMProbe consumer importing NetworkPNTRCore without @testable (compile RED).8b19034 moves only the UI-independent model/scope/callbacks/destination protocol/retirement into NetworkPNTRCore with package visibility and explicit initializers. AppKit presenter, root and views stay in NetworkPNTRMac; no package dependency or public credential API is added. Existing app model/parent/UI tests pass unchanged. The original historical receipts refer to their then-current NetworkPNTRMac paths; current source bindings use NetworkPNTRCore. This is one production implementation, not a copied harness state machine.

7c9bb1f defines missing live-controller probe preflight (compile RED).f56e388 supplies the helper and requires two completed production model reports before the captured proof can pass. An optional Int64 comparison needed correction during initial helper compilation; it was setup correction, not a business-logic RED. Read-only reviews found no migration/helper blocker. Failure paths retire every model, release the held continuation and await draining in a separate uncanceled MainActor task before propagating the original error. The controlled diagnostic never seeds a cloud profile or invokes an external target.

## Actual VM result

Signed source f56e388d882b68a6ff410d58ce31f06ac8b0ad6c; executable SHA256 852ac4a70fe92291c8a5711acd59550b05b584f6b14d32fbe60e936b69e7b34c; candidate manifest SHA256 83628454bcb2a7d4e66b3445ec1d1fd81c69926ac0eee17d06b99c0ba1931254; report SHA256 1e960ec4b3bb62de266d08425a4c20861b1e5871f93004dfeb4065ca05c1cc9b. Exit0, two boots, two cooperative stops, two clean boot audits, distinct ready boot generations, persistence/source proofs and fixed browser reference equality all pass.

On each boot the shared model obtains real structured metadata, checks the independent262401-byte original oracle, stages through AuthenticationSession/BackendJSONClient/VZ and publishes an actual file via the automated chooser. Each original.bin rereads fully equal with SHA2565549252a7f275dd6b221f062c298ac588a2dea19e5145b6ca06308cc8c9dd43e and verified file/directory flags. A second operation holds an actual authenticated verified staging receipt before returning it to the model. Retirement stops the model while staging exists and the destination is absent; releasing the late receipt creates no destination, removes staging and drains the shared collector without a cleanup notice. VM/auth generations remain unchanged during each exercise. Post-model guest audits on both boots verify source hashes and zero profile/LLM record/usage/conversation/activity/unsafe-task counts. Final fixture binding/snapshot counts remain1/2.

This is production model plus actual VM transport. The destination chooser is automated and no NSSavePanel, live native window, keyboard or screen interaction is exercised. Browser API reference projection is preserved; complete native/browser UI parity is not inferred. The existing controlled mid-transfer cancellation proof is separate from retiring a complete staged receipt.

## Regression and limits

Full Swift1020 executed,1019 passed,one existing external accessibility skip. Python179 passed. Combined unit/actual-VM file line coverage: shared model193/193, retirement29/29, helper100/115(86.96%). Broader VMController371/512(72.46%) and RootView0/420 remain disclosed; no whole-product80% claim. Core package consumer proves real module access without AppKit. No new UI design was performed in this model/transport refactor, so Lazyweb remained outside this phase; the existing save-UI design evidence still applies.

Keep real panel ownership, EN/JA layout, keyboard/multiwindow/VoiceOver and all21 browser/native workflows open until individually proven. Respect user-deferred unlock; no repeated unlock request or offscreen substitution. Preserve normal guest/profile while kernel reliability/provenance/promotion, Gemini/Groq CP1–CP4, investigation harness H0–H5 and release gates continue. Hosted CI is unverified pending quota availability check; publication uses [skip ci].

Staged app rebuild/strict signature passed. Full demangled app symbols contain NetworkPNTRCore.TrafficBodyExportModel and no NetworkPNTRMac copy. Default guest manifest fa0f1972c04f2a04853de37f4fd163b922ac38c841849c635d29f565fe6115ce and boot-file hashes are unchanged; no app launch or promotion. Release VMProbe builds, rejects captured-blob with all three positional arguments(exit2), and full symbols/new diagnostic literal exclude DEBUG proof helpers. Production model presence is checked in the app, not required in a dead-stripped release CLI.
