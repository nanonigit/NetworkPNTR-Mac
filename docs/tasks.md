# Phases and test gates

- [x] P0: baseline all navigation/page/API routes; requirements/design/parity and failure-test plan; live browser evidence; independent private repository.
- [ ] P1: real signed macOS app boots/stops Linux with no Docker dependency, no host shares or network; integrity failures prevent boot; start-stop-start and timeout/error paths verified; app window inspected.
- [ ] P2: guest ARTEX/PostgreSQL, persistence, authenticated vsock API, crash recovery; identical fixture data and auth behavior compared with reference; secrets/egress design and negative tests.
- [ ] P3: native LLM configuration, dashboard, chat, tasks/detail, findings/detail; same fixtures/success/error/stream/cancel; API access alone does not pass UI gate.
- [ ] P4: every remaining feature and detail tab mapped in feature-map.json; CRUD, import/export, notifications/interception/MCP/tools, language/accessibility/keyboard comparison.
- [ ] P5: licensed guest/source distribution, signed/notarized install, clean-Mac first run, migration/backup/restore, safe upgrade/rollback, performance and final whole-product parity.

Phase evidence: unit tests for invariants/state/integrity, real-VM integration outputs, browser/native screenshot pairs for each workflow, API-contract comparison against deterministic fixtures, and failure injection. Never count a pending screen as passed because its title exists in a sidebar. Do not use real external security targets in parity fixtures. Each matrix row must have source reference, controls, fixture, actions, expected output, native status, evidence and known differences before release.

Backend checkpoint: see docs/phase2-verification.md. Guest boot, authenticated vsock, data/auth persistence and five reference API fixture contracts pass; native auth integration is implemented but intermittent guest startup/recovery failures keep the runtime gate open. Streaming/egress, native-click/visual acceptance and broader parity remain pending.

P3 LLM checkpoint: typed profile/pool/retry services and native screens implemented; 11 normalized contract groups match the pinned reference. External create/edit/validation/keyboard-save/activation checks pass. Full LLM interaction/cloud/visual gates remain open; see docs/llm-settings-verification.md.

P3 dashboard checkpoint: all visible sections and 11 authenticated read routes are connected. 12 nonempty token scenarios match an independent browser calculation and disposable pinned reference. Partial external UI interactions passed; populated visual pairs, traffic capture and remaining error/accessibility/runtime gates stay open. See docs/dashboard-verification.md.

Portable-kernel work: pinned source/config/compiler package inventory and offline build/profile tools are implemented with 24 Python regression tests. The first offline source build, six-boot VM lifecycle suite, signed native auth/LLM/dashboard diagnostics and reference comparisons pass. Independent same-host builds match kernel/config/build-report hashes. License contents match but archive directory times differ; whole-builder identities differ and cross-host/package reproducibility is not accepted. Runtime promotion and reliability acceptance remain open. See docs/kernel-build-verification.md. See docs/kernel-build-design.md and docs/bugs/guest-boot-investigation.md.

P3 chat checkpoint: C1 typed finite services/state store pass 24 scoped tests (66 Swift total). C2 basic CRUD/empty transcript has ten matching groups on the signed source-kernel VM and disposable pinned reference. 28 Python tests pass, including reference isolation. Populated guest history, AI running/send/stop, UI and advanced parity remain pending. See docs/chat-verification.md and docs/bugs/chat-state-investigation.md.

P3 chat populated checkpoint: latest 200 + older five from 205 fixed events, overlapping delta and final six to 211 match ten pinned-reference groups. Two fresh signed native runs pass; the second proves exact full-history/detail persistence after VM restart and authenticated cleanup before dashboard seeding. Current local regression: 66 Swift / 34 Python. Chat UI and successful AI/running stop remain open. See docs/chat-verification.md.

P3 C3 checkpoint: native rail/transcript/composer implemented; partial external browser/native comparison and scroll/draft/IME regressions pass. 75 Swift (74 core + 1 AppKit) and34 Python tests pass. Chat is in_progress; native running stop, multi-delete confirmation, cloud response, advanced controls and full visual/accessibility gates remain pending. See chat-verification.md.

C4 citation finite core: seven tests and eleven executed browser-token cases pass;82Swift total. Native autocomplete/insertion, actual VM/search-page comparison,128MiB streaming uploads and side-question SSE remain pending. See chat-advanced-design.md and chat-verification.md.


C4 interaction checkpoint: native citation controls, nine executed browser editing cases and real23-record VM/reference paging contracts are implemented and partially externally compared. Current95 Swift (90core+5AppKit) /34 Python tests pass; rebuilt ad-hoc app verifies. Repeated insertion/Undo have component regressions; pointer paging viewport repair awaits external retest after Mac unlock. Resume with fresh VM and owned reference marker paths; test pointer viewport, repeated insert/Undo, all categories, physical IME and VoiceOver before closing citation UI acceptance. Attachments128MiB, side-question SSE, rich rendering/approvals, real cloud turns and all21 full feature gates remain open. See chat-verification.md and bugs/chat-state-investigation.md.


A1 attachment body reader implemented and scoped-tested: whole multipart128MiB bound,64KiB chunks, observed file-change rejection, terminal cancel and three secondary FormData wire cases.106 Swift tests pass; app rebuilt/signature verified. A1 core only, not upload transport or parity acceptance. Next A2 adds authenticated multipart session/runtime capability with real socket backpressure/cancel/early-response/failure tests; A3-A5 and citation external retests remain open. See chat-advanced-design.md and chat-verification.md.


A2 checkpoint: authenticated multipart client/runtime, cancellable owned descriptors and post-await leases implemented;11 socket/6 auth-client/1 fixture tests,124 Swift total pass. Signed fresh VM retry uploads/downloads3synthetic files with exact bytes/SHA256 and cleanup; the first source-candidate attempt panicked beforebootstrap and remains counter-evidence for runtime reliability. A2 live stop/cancel and A3 actual128MiB/reference comparison remain open; next formalize disposable pinned upload contracts, exercise upper bound/stop and then A4/A5 state/UI gates. No source-kernel promotion. See chat-verification.md and bugs/guest-boot-investigation.md.


A3 API boundary checkpoint: signed fresh VM and disposable pinned browser backend agree on3small-file hashes/order/names, actual exact128MiB multipart acceptance/persisted size and one-byte-over rejection/original preservation.125 Swift and39 Python tests pass. Native preflight and backendHTTP400 are distinct validation layers; no UI gate closes. Next add bounded native large-content download/hash and real VZ transfer cancellation/progress, then A4 attachment state and A5 picker/cards comparisons. Kernel reliability and all21 full feature gates remain open. See chat-verification.md and upload-a3-verification.json.

A3 content extension ordered gates: incremental bounded digest parser RED/GREEN; real socket download/cancel/deadline RED/GREEN; authenticated attachment-only client/runtime revision/lease tests; fresh signed VM full128MiB-boundary file SHA versus independently streamed pinned reference; cleanup and remote CI. Do not accept metadata alone as large-content verification. UI, live VZ cancellation/progress, measured memory and runtime reliability remain separate pending gates.

A3 full-content checkpoint: bounded digest parser, actual socket cancellation/deadline/framing and authenticated revision/runtime leases implemented through RED/GREEN. Fresh signed VM and pinned disposable reference fully hash134,217,517 bytes with identical SHA and eight matching groups; owned data cleaned.145 Swift/42 Python pass. Next actual VZ stop/cancel during transfer and progress, A4 attachment draft state, A5 external UI. Measured process memory, source-kernel reliability and all21 complete feature gates remain open.

Attachment progress/live cancel gates: reporter and real-socket callback RED/GREEN; auth revision/terminal progress lifetime and post-await cancellation RED/GREEN; real signed-VZ task cancel and VM-stop-on-partial progress, authenticated restart/owned cleanup; full suites/build/review/CI. Numeric transport counters do not close browser/native spinner or attachment UI gates.

Upload progress/live interruption checkpoint:157 Swift (145core +5AppKit +7diagnostic fixtures),42 Python pass. Fresh signed upload-cancel-a3-v2 cancels an upload after17,852,806 reported body bytes and remains usable; another transfer stops after17,579,466 with exactly one active owned socket cancelled by VM stop, CancellationError, authenticated restart, no persisted partial attachment and owned cleanup. The initial162-byte/no-witness run is explicitly not accepted. Full128MiB upload/hash and eight pinned reference groups still match. Actual download cancellation, multipart-spill cancellation, measured process memory, A4 draft ownership/A5 UI, citation external retests and runtime reliability remain open. Next implement native attachment state/handoff/removal/send-restoration with browser-derived behavioral cases, then picker/cards controls and external comparison.

A4 ordered implementation: typed validated attachment/envelope and send wire; keyed local cards, optimistic clear/failed restoration/new-edit/reset/stop tests; then authenticated upload adapter and draft-create/handoff, source-derived reference cases, signed runtime, and native picker/cards comparison. Do not call A4.1 service/state work full attachment parity.

A4.1 checkpoint:171 Swift (159core +5AppKit +7diagnostic fixtures),42 Python,39 scoped chat tests pass. Typed relative metadata, exactUTF8 identity, keyed local cards, optimistic send/failure/stop recovery and attachment-only workspace sends implemented. Four checksum-pinned browser ChatView send executions match pending/final state and wire. Source oracle regeneration and rejection-before-evaluation pass; app rebuilt/signature checked. No native picker/card/upload-handoff acceptance claimed. Next A4.2: authenticated typed upload adapter, create-on-selection/text handoff, conversation deletion and stale upload/cancel/reset ownership; then actual guest/reference fixtures and A5 UI. Unicode input trimming edge parity remains required.

A4.2 ordered tests: authenticated typed adapter RED/GREEN; workspace origin/target singleflight and text/card handoff; controlled stale create/upload/progress/cancel/stop/reset/delete and per-conversation send invalidation; full suites/build/review; then real guest/source-derived baseline integration and A5 UI. Retain exact UTF8 attachment identity and all four existing browser send cases.

A4.2 finite ownership/runtime checkpoint:190 Swift (176core +5AppKit +9diagnostic fixtures),45 Python,46 scoped ownership/existing-chat cases pass. Typed authenticated upload, create/text/cards handoff, progress latest-one delivery, stale/cancel/replacement/stop/reset/delete ownership implemented and reviewed. Fresh signed attachment-handoff-a4-v1 failed before bootstrap with blank-check segfault/kernel memory warnings despite an entirely zero disk; preserve it. The single same-profile control attachment-handoff-a4-v2 exercises actual typed vsock handoff, two no-LLM503 recoveries, content hashes, card removal/file preservation, selection isolation and owned cleanup; six pinned disposable backend groups match. This does not close source-kernel reliability or UI gates. Next A5: current Lazyweb evidence, native picker/cards/progress/error/cancel controls and external browser/native comparison; retain Unicode trimming, spill/download cancellation and known runtime fault investigations as open gates.


Unicode send gate before A5: execute expanded pinned oracle; validate RED on store/wire/restoration and pre-create/service guards; checkpoint; shared scalar trim and GREEN checkpoint; review, full suites, coverage, signed rebuild, CI. Native UI and actual provider acceptance remain pending.


Unicode core GREEN:193 Swift/45 Python, nine source-send oracle cases, reviewed shared trim,100% helper line/region/function coverage and signed rebuilt bundle. UI gating remains A5; no UI/runtime acceptance closed. Next resume Lazyweb research and native picker/cards/progress/cancel/error controls against the fixed browser, including the pending send-button guard.


A5 ordered gates: availability/progress/size/file-scope/native-panel configuration tests RED checkpoint; minimal controls/helpers GREEN checkpoint; review; full suites/coverage and signed bundle; actual native picker cancel/multiple files/cards/removal/no-LLM send restoration/progress/cancel and keyboard versus disposable pinned browser, with screenshots and retained boot faults. Fix any failures with scoped RED/GREEN; leave unobserved cases pending.


A5 partial checkpoint: native controls implemented/reviewed,205 Swift/45 Python and strict signed build pass; actual panel/cancel/cards/removal/oversize repair and partial-progress Cancel observed. Browser pre-send metadata/text match; send-error fixtures differ and reference runner timed out after observation/cleanup. Next make a fresh no-LLM native review fixture before LLM diagnostic seeding and compare failed restoration; add sent-attachment transcript rendering; complete progress visual/keyboard/VoiceOver and citation retests. Keep all21/full runtime gates open. See bugs/chat-attachment-ui-investigation.md.


A5 compatibility check: explicit MainActor scoped-operation closure resolves the CI compile failure;206 local Swift tests pass. Check the new remote CI. Unmatched restoration/transcript attachments/progress synchronization/accessibility/runtime reliability gates remain open.


A6 ordered gates: checksum-pinned parser fixtures and model RED/GREEN; MainActor row loading ownership/inline/error/empty/retry/cancel/stale/defer tests RED/GREEN; read-only native cards and user text UI, reviewer; full suites/coverage/build and actual persisted attachment VM/browser fixture with screenshots, owner isolation and cleanup. Keep other A5 and full-product gates open.


A6 persisted-body checkpoint: 221 Swift cases (220 pass, one explicitly skipped in-process SwiftUI AX case),49 Python pass. Twelve checksum-pinned parser cases regenerate identically and reject altered source before evaluation. Fresh signed native VM and disposable pinned browser persist identical full-body/attachment-only/duplicate-reference contracts. External CUA confirms both readonly cards including NFD54B/empty0B, literal asterisks/newline, duplicate cards and no remove actions; empty composer/send disabled. Both owned fixtures cleaned and processes terminal0; VM stopped/keychain removed. Core parser/store line coverage100%, store regions94.3%; new user view77.1% lines, error/retry UI not externally accepted. See user-body-verification.json and bugs/chat-user-body-investigation.md. Next matched no-LLM send restoration, external detail-error retry, long-history scroll/memory and VoiceOver; retain progress synchronization and source-kernel reliability/all21 gates.


A7 gates: plan/zero-profile validation tests RED; DEBUG fixture integration GREEN; review/full suites/signed rebuild; fresh owned native+browser no-LLM UI sends in mixed and attachment-only forms, exact draft/card restoration/history/files checks and cleanup; remoteCI. Do not infer UI restoration from earlier model tests alone.


A7 observed-error repair: exact static no-profile mapping RED -> service boundary GREEN -> full suites/review/build -> fresh native UI retest, retaining first-run misleading-error screenshots. Draft restoration is observed, but error UX parity stays pending until that retest.


A7 checkpoint: DEBUG no-provider plan implemented/reviewed; matched native/pinned-browser mixed and attachment-only failed sends restore original text/two36B+0B cards in actual UI. Native zero profiles verified before/after restart. First-run error UX failed: native called no-profile503 a database outage. Exact five-catalog static mapping repaired by RED5assertions/GREEN7service tests;224Swift cases(223pass/oneAXskip),49Python. New plan100% lines, ChatService96.95%. Both processes exited0; VM stopped/keychain removed and reference resources removed. Native private disposable disk retains fixture files; individual guest file cleanup/content hashes not reverified. Next fresh signed native UI retest of2285311 error guidance, rejected-history/files inspection/cleanup, then remaining A5 progress/accessibility and long-history/all21 gates. See restore-verification.json.


A7 repair external retest: fresh signed native V2 at2285311 shows the static LLM setup instruction after a text-only rejected send, preserves the exact draft and empty conversation. Screenshot/AX and repaired native-results saved; process terminal0, VM stopped and temporary Keychain removed. This supersedes the pending repair-guidance check above; mixed/attachment-only restoration evidence remains from12a8a8e. Individual uploaded-file cleanup/hash/API history, long-history/accessibility/progress/kernel and all21 gates remain open.


Localization release gate (R8): audit hardcoded native strings and backend builtin/generated content; en/ja-only persistent switch and String Catalog; backend output-language synchronization; first-run/switch-both-directions/restart/existing-state tests; all21 feature/error/empty/loading/confirmation/accessibility checks in both locales against fixed browser flows. Preserve custom/user/model content, record intentional language-support divergence. Initial audit is recorded; implementation and full acceptance are pending. Do not close this goal with Japanese-only UI.


L1 ordered gates: language/locale/default precedence/migration/persistence and unrelated-default isolation tests RED; minimal typed observable preferences GREEN; reviewer/full suites/scoped coverage/signed build/CI. Then en/ja String Catalog plus actual native switch, preserve composer/selection while switching, propagate backend output_language with failure/rollback semantics, all21 rendered audit. No UI acceptance from preferences tests.


L1 checkpoint:690c4e1 implements only typed persisted en/ja preferences. Five focused tests pass, both new files100% line/region coverage; full229Swift cases(228pass/oneAXskip) and49Python pass; reviewer approved. Saved-value precedence, invalid-to-English repair and isolated suites/unrelated defaults verified across new instances. Actual UI switch/catalog/backend sync and app-process restart remain unverified. Next L2: current Lazyweb evidence before UI, String Catalog/resources, native switch without rebuilding/resetting chat state, rendered two-locale comparisons; then backend synchronization with explicit failure semantics. Full goal stays open.


L2 ordered: compiled-catalog explicit en/ja/feature-title and fallback tests RED; resources/helper GREEN; native picker/root integration and reviewer; full tests/coverage/signed resource verification; real two-direction UI switch and active composer/selection/VM preservation comparison. Keep feature-inner strings and backend sync open.


L2 shell checkpoint: compiled String Catalog/helper and native toolbar en/ja picker implemented. Actual signed5a66610 ja->en->ja keeps literal draft/23B card/Chat and conversation; new process retains en, original ja restored. Pinned browser settings en->ja->en observed, with5options versus intended native2. Six Japanese feature names corrected after screenshots: d949dc8 RED6,ad9a7fe GREEN5catalog tests; final signed compiled resources verified. Full234Swift(233pass/oneAXskip),49Python; helper100% lines/97.4% regions. Initial incremental catalog lookup93failures followed by unchanged probe and clean scratch success: root cause unproven, preserve counterevidence. Both VM diagnostic processes/reference terminal0 and stopped/cleaned keychain/resources. Feature interiors/backend sync/default Chinese/Korean names/system menus/raw lifecycle statuses/VoiceOver remain open, along with runtime/all21 gates. Next L3 localize migrated screen interiors and safe error catalog, preserve custom content, then backend language synchronization with explicit failure status.


CI portable-resource gates: retain failed hosted test as actual RED; exporter schema/determinism/stale check tests RED then GREEN; portable resources/CI/build integration; local legacy native build-system cold tests and signed resource check, reviewer, remoteCI. Do not retry the same incompatible artifact hoping for green.


L2 portability checkpoint: initial hosted40110609236 failed because legacy SwiftPM copied catalog without compilation. Strict exporter+generated portable en/ja resources and drift checks repaired it;5cold legacy catalog cases,234default Swift cases(233pass/oneAXskip),52Python pass; exporter94.6% line coverage. Final signed bundle verification and remoteCI required; whole language/backend/all21 gates remain open.


L3 gates: builtin default/custom preservation and chat catalog tests RED/GREEN; localized AppKit button/panel/editor/progress tests RED/GREEN; controls/empty states integration, reviewer/full tests/coverage/signed build; actual en/ja Chat with literal draft/file/caret preservation and pinned browser comparison. No whole Chat/R8 acceptance until remaining errors/default-title/backend/accessibility gates pass.

L3 checkpoint: localized Chat controls/defaults verified with240Swift cases(239pass/one existingAXskip),52Python and clean signed build. Actual native/browser en->ja retained literal mixed-language draft and21B card. Screenshots at2a62b55 precede complete builtin wording at5232876; final resources separately verified. Korean default title remains pending because explicit localized creation breaks backend automatic naming. Whole-state fixture cleanup complete; individual file hashes not claimed. See [Chat localization verification](localization-chat-verification.md). R8/Chat/all21 gates remain open.

L4a error foundation: replace native static validation payload strings with typed BackendValidation values and a bilingual error presenter. Preserve existing Japanese LocalizedError compatibility during staged store migration. Explicit language lookup must not inspect OS preferences or stringify unknown errors. Status/Keychain numeric codes may be interpolated, but arbitrary server bodies/paths/secrets must never be presented. This infrastructure stage does not close UI error switching or R8.

L4a verified: ea39007 intended missing-presenter/reason RED -> a3f7681 GREEN3; full243Swift(242pass/one existingAXskip),52Python; presenter26/26lines and21/21regions. Final signed bundle29error entries per language match catalog; reviewer approved. Store/UI locale integration still pending; see bugs/error-localization-investigation.md.

L4b Chat errors: store safe typed AppErrorMessage values, render at current view locale without replacing views, issuing requests or mutating draft/attachments/selection. Keep computed Japanese String compatibility for diagnostics/old tests. Cover list/history/send/stop/workspace/upload/partial-delete/mention pagination/body/details; preserve cancellation/generation/owner checks. Unknown errors reduce to a typed fallback without retaining raw data. RED/GREEN store tests, full regression, reviewer, signed build, then actual native/browser failed-send locale comparison are distinct gates. Lazyweb query chat error retry message returned weak adjacent DoorDash metadata (similarity.385), not visual proof; existing fixed error UI remains authoritative.

L4b checkpoint:96eae3e RED missing typed store failures ->0796897 GREEN3;246Swift(245pass/one existingAXskip),52Python; safe-value13/13lines,11/11regions; signed app and33error strings per locale verified, reviewer approved. User deferred Mac unlock, so actual native/browser failed-send locale UI gate remains open. No new runtime fixture started. See localization-chat-errors-verification.md.

L4c migrated screen error/notice gate: AuthenticationSession, LLMStore and DashboardLoadState retain AppErrorMessage identity, with Japanese computed String compatibility. LLM confirmed notices retain catalog keys, independent of failed refresh; resolve error/notice text at current view locale in auth, LLM settings/editor/rotation and dashboard. No locale-triggered authentication/mutation/poll reset or password/API-key persistence. Keep forms, terms agreement, generation and last-good data unchanged. Surrounding untranslated controls and terms language remain separate gates. Tests cover validation, unknown-error sanitization, confirmed-save/failed-refresh and cached-dashboard preservation. Lazyweb settings inline validation error returned weak adjacent Gopuff captcha metadata(.356), not inspected visual evidence. Actual native/browser switching remains deferred until user unlocks Mac.

L4c checkpoint:a229ee3 intended missing typed values RED->7b6c8c5 GREEN4;4cbb734 adds action/poll regressions GREEN7. Final253Swift(252pass/one existingAXskip),52Python; signed error/notice39entries per locale match catalog. Auth/LLM/Dashboard safe errors and6notices connected; reviewer approved. Native/browser, surrounding labels/terms and runtime/backend/full gates stay pending. See localization-screen-errors-verification.md.

L5 authentication/terms: translate all native auth labels via typed catalog; load both pinned terms documents once with a typed AuthTerms.loadAll API and resolve current locale in the existing sheet. Preserve password/confirmation/agreed/focus bindings, task identity, submit behavior and phase-clear boundaries. Follow pinned browser read gate: reset per sheet opening, preserve readToEnd within the open sheet across locale changes; no new language-keyed view identity. Full28-entry terms documents must exactly match fixed auth.terms per locale; no legal-content rewriting or runtime network. Native-specific automatic setup-token handling and fixed username keep accurate native instructions. Resource/API tests RED/GREEN, review/full tests/signed resources; live native/browser controls/scroll/read gate remain pending until Mac unlock. Lazyweb terms agreement modal: moderate Postman metadata(.479), not inspected visual proof.

L5 adjacent read-gate repair: initial empty scroll geometry must not grant read completion before a document is loaded. Track a safe per-sheet reading progress and include documentLoaded in the Equatable viewport observation so a newly loaded short document can become readable even if atEnd remains true. Failed/empty documents cannot enable Agree; loaded document end latches within open sheet across locale, fresh sheet starts unread. This is a functional read gate, not stronger login authorization; the existing explicit agreement checkbox remains unchanged. Separate RED/GREEN and deferred actual scroll comparison.

L5 checkpoint:b4c3172 missing keys/loader RED->3c70904 GREEN3,cc1e53c reading-state RED->a9e3fa3 GREEN5.258Swift(257pass/one existingAXskip),52Python; loader/reading100%lines; signed23auth strings and28terms entries per locale exact. Reviewer approved dataflow, actual geometry delivery/secure fields/browser comparison pending user unlock. Other screen/backend/runtime/all21 gates remain open. See localization-authentication-verification.md.

L6 LLM UI: migrate settings/cards/editor/model picker/rotation/global retry/numeric validation/help to typed en/ja catalog. Add single-pass named placeholder formatting so opaque model names, masked key hints and values cannot be recursively reinterpreted as template tokens. Preserve tags/raw API enums/prefix keys/bindings/invalid text/dirty flags/sheet ownership and existing fieldGeneration only on confirmed reload/save. No locale id/task or network/mutation changes. Research Lazyweb AI model provider settings returned moderate V7 metadata(.535), not inspected visual evidence; fixed LLM browser remains reference. RED/GREEN catalog/format tests, full regression/review/signed bundle; actual native/browser switching stays deferred by user Mac unlock.

L6 checkpoint:e377f16 formatter/catalog intended RED->c855245 GREEN3;261Swift(260pass/one existingAXskip),52Python.108LLM UI strings/11templates localized; single-pass helper100%lines, signed108entries per locale and placeholder parity verified;5source files CJK0/Picker tags unchanged; reviewer approved. Literal model/user/backend content preserved. Actual numeric input/layout/sheet/browser acceptance deferred until unlock; all21/full gates remain open. See localization-llm-ui-verification.md.

L6 CI correction:40135493632 failed2raw JSON Data comparisons.1da4b81 canonical semantic comparisons+controls focused3pass; d09e852 mislabeled GREEN during compile failure is INVALID evidence. Production unchanged; final hosted rerun must pass.

L7 Dashboard UI: localize headings, groups, empty/stale/loading states, selectors, chart axis/series/legend/accessibility, summaries, period counts, asset/traffic/system panels. Keep metrics/calculations/date identities/queries/polling/selection IDs/tags/navigation unchanged. Known task/engine/severity labels match pinned status dictionaries; exact raw identifiers only, unknown text preserved. Activity types localize known5codes while custom tool names/workers/summaries remain literal. Chart series and legend scale use matching localized keys; color/selection parity needs actual UI. Reuse single-pass opaque formatting. RED/GREEN resource/status/metric invariance tests, review/full tests/signed resources; native/browser remains deferred until unlock. Lazyweb usage analytics dashboard: strong Google Analytics metadata(.631), not inspected visual proof; fixed browser is authoritative.

L7 checkpoint:9a2e383 intended missing dashboard labels RED->a41c2fa GREEN3;264Swift(263pass/one existingAXskip),52Python; display helper100%lines. Signed103entries per locale/16template tokens match;15pinned statuses, unknown/tool content preserved. Core metrics/models/service/store unchanged, tags/colors source-audited, reviewer approved. Actual native/browser chart/layout/selection/VoiceOver deferred until unlock; full21/runtime/backend gates open. See localization-dashboard-ui-verification.md.

L8 runtime/parity: translate controls, six lifecycle states, sidebar status and feature-comparison table/counts at current locale. Preserve nativeStatus gate, feature IDs/browser paths and unknown feature titles. Store a safe AppErrorMessage alongside existing raw diagnostic strings in VMController/DesktopRuntime; clear it at the same start boundary, set it only in existing fail/catch boundaries. RuntimeError classes map to safe catalog keys, never interpolate arbitrary stage/path/detail; unknown framework errors get a runtime-specific fallback. No VM config/capabilities/protocol/state transition/auth/disk/poll changes. Keep raw guest logs and CLI diagnostics unchanged. RED/GREEN resource/state/failure boundary tests must not launch a VM; review/full tests/signed resources. Actual native/runtime controls and standard OS menus remain pending; SwiftUI locale alone does not localize standard AppKit menus. Lazyweb virtual machine status settings returned weak adjacent Height metadata(.383), not inspected visual proof.

L8 checkpoint:346f7b4 intended missing presentation RED->a4e9c7b GREEN4;268Swift(267pass/one existingAXskip),52Python; runtime/error helpers100%lines. Signed34strings per locale/3templates match. Safe parallel error state preserves raw diagnostics and exactguard/reset boundaries; state/config/protocol/disk/auth flow unchanged by source reversal/hash audit. Reviewer approved; new tests stop beforeVM/disk. Native runtime/menus/Rootcatalog/backend/provenance/full21 gates remain open. See localization-runtime-ui-verification.md.

L9 menu boundary: retain existing NSMenus/actions/responder chain/shortcuts/targets/enablement. Translate only recognized native action+known static title pairs; registered window/help/services menu identities and guarded root header names identify standard groups. Unknown/custom/attributed/custom-view items and dynamic window/service names stay literal; do not rebuild menus. Update from app language and at AppKit didBeginTracking, resolve current main menu each time (SwiftUI may replace it). One selector observer with explicit stop; no timer/action invocation/persistence/VM changes. TDD synthetic-menu metadata/roundtrip/unknown and observer replacement/stop tests plus28-key catalog; actual OS menu dispatch and all dynamic/unknown coverage remain pending until unlock. Lazyweb desktop application menu bar returned weak adjacent Cluely metadata(.340), not inspected visual proof. Use the narrow AppKit interop boundary per installed skill; SDK NSMenu notifications and NSApplication registered-menu properties checked locally.

L9 static-menu checkpoint:8d65447 missing adapter/keys RED->bab27b4 GREEN5; b97a197 Close Window runtimeRED1->b757992 GREEN7.275Swift(274pass/one existingAXskip),52Python; Mac-object menu coverage100%lines/96%regions; signed28menu entries per locale match.22native selectors preservemetadata; observer replacement/stop tested, reviewerapproved. DynamicUndo/ExitFullscreen/ShowHide/SwiftUI selectors and actual firsttracking/dispatch remain unproven until unlock; do not mark OS-menu/full21 acceptance complete. See localization-menu-verification.md.

T1 Tasks finite core follows tasks-core-design.md: all current create options plus list/detail/metadata/control/batch/delete, strict identity and mutation outcomes, bilingual typed validation; no active selection side effect, no UI completion claim. RED/GREEN/full regression/review/signed build precede real VM/reference and UI acceptance.

T1 checkpoint:36b227b intended missing API compile-timeRED→3f47d06 GREEN8. Expanded full287Swift(286pass/one oldAXskip),52Python; final focused13pass includes pre/post-dispatch cancellation. Three new files100%lines/regions; signed build and5validation strings per locale checked; reviewer approved. Source fixture hashes match pinned baseline; no live backend/UI/VM request. Tasks remains pending; state/UI/reference/runtime/full21 gates open. See tasks-core-verification.md.

T2 Tasks state follows tasks-state-design.md: observable list/detail read states and selected ID, race/lifecycle guards, explicit confirmed/rejected/unconfirmed mutation outcomes for all finite T1 operations, retained confirmation across refresh failure, no automatic mutation retry or active selection,10-second cancellable polling. No screen/feature/runtime acceptance. Backend state only; Lazyweb out of scope. RED/GREEN, controlled response-order/cancel/reset tests, full regression, review and signed build required.

T2 checkpoint:9e10d78 missing-storeRED→732ab69 GREEN10;8ceabdf expanded13;1efb06f cancelled-navigation runtimeRED1/7assertions→e950f21 GREEN14. Final302Swift(301pass/one oldAXskip),52Python; store99.26%lines/94.55%regions, reviewer approved, signed build/strictcodesign pass. State only; UI unconnected, no live request/VM/hostAI. Per-session single-store/reset/uncertainty presentation remain integration obligations. Tasks/full21/runtime/distribution gates open. See tasks-state-verification.md.

T3 follows tasks-ui-design.md: wire native list/detail, search/status/sort and finite rename/pin/control/delete actions to the retained per-window T2 store, authenticated routes and dashboard task navigation. Bilingual controls, safe uncertainty and five default-off cleanup flags; no language-driven view replacement. Feature becomes in_progress only. Creation, categories/archives/bulk/advanced detail and runtime comparison remain required later. RED/GREEN presentation/controller/layout tests, review/full regression/signed build; actual native/browser comparison deferred until unlock.

T3 checkpoint:0c01a4b missing presentation/controllerRED→f0e460b GREEN6;80ca7c3 missing token/error identityRED→b38f3b3 GREEN8;51c0531 queued-owner runtimeRED1/2fail→e286140 GREEN9;d1d2464 bindingRED→741717f GREEN14. Final316Swift(315pass/oldAX1skip),52Python; presentation91.36%lines/model98.46%; UI coveragepartial. Signed build/strictcodesign and57keys/locale match; inventories21/27/243 synchronized, Tasksin_progress,17screenspending. Reviewapproved. No live requests/VM/visibleUI/install; creation/bulk/categories/advancedTasks/full21/runtime/distribution remain open. See tasks-ui-verification.md.

T4 follows tasks-create-design.md: implement creation option catalogs and all12T1body fields in native form with ordered profiles, source/company/category selectors, template application and stable rule rows. Captured context IDs guard all inputs, async loads and submit/close. Creation is explicit once; confirmed clears even if refresh fails, unknown retains draft and blocks resubmit. Native attachments/template/category management and whole-task/runtime/UI parity remain open. RED/GREEN, controlled race tests, full regression/review/signed build; actual comparison after unlock.

T4 checkpoints:889b32d→c1b9fe4 CoreGREEN3;6c85680→d8ea915 controllerGREEN4;ee46711 real-ID/BOM runtimeRED4fail→8105e5c GREEN8;cfa4c93→bc4c674 UI GREEN10;d5b6a25 expanded14;e1edf9f overwrite runtimeRED3fail→f56c82a GREEN15;fe75585 Unicode runtimeRED12fail→a8e3302 GREEN16. Full332Swift(331pass/oldAX1skip),52Python; signed build/strictcodesign/42keys per locale pass. Creation Core/model line coverage93–100%, UIbranchcoveragepartial, reviewapproved. Native uploads/management/realcreate+validation/parity/full21/runtime/distribution open. See tasks-create-verification.md.

- [ ] Extend raw FEFF/NFC/NFD regressions to other remaining service list projections; T4 fixes only its own catalog decoding.

B1 boot diagnostics follows boot-preflight-design.md: separate blank/nonblank from scan execution failure, preserve fail-closed formatting, add private one-boot read-only VMProbe preflight with fixed sanitized report. Use only fresh disposable state and verified separate candidate; no user-data/guest-policy change. TDD/report/guard tests, controlled old/new-profile single experiments, review/full regression/signed build. Kernel reliability/root cause and visible parity remain open; no Lazyweb for infrastructure.

B1 diagnostic checkpoint: status classification and complete-log audit implemented/reviewed;337Swift cases (336pass,1existingAXskip),54Python pass; old/new isolated single-boot controls pass. Prior faults/reliability/UI/egress remain open. See boot-preflight-verification.md.

T5 staging transport follows tasks-staging-design.md: authenticated finite UUID staging upload using existing bounded multipart/vsock transfer and session revision/progress guards. Validate exact guest draft paths and preserve raw Unicode; never turn guest paths into host URLs. TDD malformed/status/count/stale-auth/cancel/header tests, review/full regression/signed build. Creation-model/UI/description manifest and actual VM/browser upload acceptance remain next gates; no UI work or Lazyweb in this transport phase.

T5 checkpoints:0c5b0cb RED→e84f3be GREEN5;4e36255 aggregate runtimeRED1/7→dae79a8 GREEN7;3efadea concreteclientGREEN8.345Swift(344pass/oneexistingAXskip),54Python; stagedmetadata/header100%lines/regions, sharedauth100%lines. Signedbuild/strictsignaturepass, sourcebaselineclean/inventoryunchanged, reviewed. Creationstate/UI/en-ja manifest/liveupload/parity remainopen. See tasks-staging-verification.md.

T6 follows tasks-staging-ui-design.md: connect T5 transport to retained creation draft ownership, explicit selected-file picker, cancellable progress and exact en/ja browser manifest. Preserve text across close, rotate draft on discard/reset/confirmed create, guard stale operations and block submit during upload/picker. TDD and review/full regression/signed resources; no actual UI parity until unlock.

T6 checkpoints:5bd60c9→435b654 CoreGREEN3;654cc90→215d3ed modelGREEN4;ef21ef4 oracle126;ebd3176→e2b1541 UI GREEN5;60a267b→603a47a scopedboundaryGREEN6;a19a09d GREEN7;4f8514a actualparentstopRED9assertions→66440ab GREEN12;1c73474→72115f3 pickerGREEN27 (title28isincorrect);f5d6b02/d63a0b3 expanded. Final358Swift(357pass/oneexistingAXskip),54Python; signedbuild/8enjakeys exact, reviewapproved. Nativecontrols/manifestconnected, actualUI/securityscopedfile/VM+browsertransfer/full21/runtime/distribution remainopen. See tasks-staging-ui-verification.md.

T7 follows task-staging-runtime-design.md: bounded one-boot actual staging/upload/download collision exercise on a fresh private source-kernel candidate, compared with a fresh pinned Docker reference; no agent/task/conversation/cloud or user data. Fixed synthetic fixtures, normalized full-log audit and preserved failures; TDD/negative fixtures/review/regression before hardware. UI/OS-picker/restart reliability remain separate open gates. Infrastructure only; Lazyweb out of scope.

T7 checkpoints:30339f0 missingAPIRED→1fd297b filename runtimeRED3/4→7a9b58e GREEN4;ab1c1be→56ba489 PythonGREEN2;f2adde4→0504549 reportGREEN5/environment3;26cd220→10b82f5 cleanupGREEN3.363Swift(362pass/oneexistingAXskip),60Pythonpass; signedoneboot actualstaging14.85s exits0,8records/en-ja manifests match separate pinnedreference,12byte-readbacks/no-clobber. ReferenceA/B failedpreparations retained, correctedCpass; allreference resourcesremoved/originalbrowserunchanged. Appbuild/strictsignaturepass; UI/taskcreate/restart/kernelreliability/cloud/full21/distribution remainopen. See task-staging-runtime-verification.md.

T8 follows task-template-management-design.md: full native template manager (list/new/create/edit/delete, category and interception rules), save-as seed from creation, safe uncertainty and captured ownership, en/ja labels. Source contract/negative tests RED/GREEN, review/full regression/signed resources; actual OS/UI/live workflow comparison stays open. Fixed baseline and VM isolation unchanged.

T8 checkpoint: Core contract4 and manager/integration12 cases pass. Final379Swift (378pass,1existingAXskip),60Python pass; code coverage lines service93.27%,manager92.11%,offscreen UI83.20%. Signed build-only succeeds; strict signature verification and all21new entries per en/ja match the packaged catalog. Reviewed mutation/read/reset/sheet/discard ownership fixes. Pinned inventory21/27/243 unchanged. No new dependency manifests; npm/pip audits not applicable. Actual OS/UI/live CRUD/browser comparison pending later unlock; Tasks/full21/cloud/kernel/release gates remain open. See task-template-management-verification.md and bugs/task-template-ownership-investigation.md.

T9 implement category Core CRUD/single/batch assignment from task-category-core-design.md; RED/GREEN, Unicode/IDs/schema/null/partial/status/cancel tests, review/regression/coverage/signed build. Category manager/inline create/filter/move UI and actual VM/browser parity remain open.

T9 checkpoint: RED1f3ad33 -> GREEN334935a7cases, expanded8cases. Full387Swift (386pass/1existingAXskip),60Python pass; category service100%lines/regions/functions. Reviewed finite CRUD/assignment/partial/null/Unicode/bounds; signed build/catalog3en-ja entries verified. Fixed baseline hashes retained in evidence/tasks/t9-core-verification.json. Actual category UI/state integration/inlinecreate/filter/moves/livecomparison remain required; full21/runtime/cloud/release gates stay open. See task-category-core-verification.md.

T10 implement native category state, confirmed projections and filter, UI and inline integration with TDD ownership/unknown/read-reset tests, en/ja offscreen checks, review/full regression/signed build. Real Mac comparison remains deferred by user unlock.

T10 checkpoint:15workspace/3projection cases; final405Swift (404pass,1existingAXskip),60Python pass. Coverage lines projection100%, workspace96.36%, offscreenUI70.42% (actual action/layout acceptance remains open). Runtime RED dismissal01c7664/duplicate2b565ce/initial4ba1e25/cancel338324b retained; fixes reviewed. Build-only/strictsignature/26en-ja values+placeholder parity pass; fixed21/27/243 unchanged. Core grouping and native manager/inline/filter/moves wired; general main-table bulk and actual browser/native/VM durability/AX/keyboard/drag/UI comparison after unlock remain required. No VM/cloud/default-image change. Full21/kernel/release gates open. See task-category-ui-verification.md and evidence/tasks/t10-ui-verification.json.

T11 implement Core catalog exercise and VMProbe --task-catalog with malformed/freshness/cancel/terminal-failure tests; reviewed full regression and signed probe before one actual VM experiment; pinned disposable Docker reference, compare and remove only owned resources. UI unchanged/Lazyweb out of scope.

T11 checkpoint: b0bf5b8 RED→0f164d3 GREEN4; ed12533 receipt runtimeRED→f770278 GREEN6. Full411Swift (410pass/1existingAXskip),62Python pass, newexercise/report100%lines; signed app/probe and existing-output rejection pass. One actual fresh VM15.33sec exits0, protected401/isolation/full-log audit/cooperative stop;12catalog checks and literal fields exactly match separate pinned reference. Owned reference resources/credentials removed, original4browser IDs/artifact hashes unchanged. No task/agent created, no candidate promotion. Live task moves/creation, restart durability, actual UI comparison/full21/cloud/kernel reliability/distribution remain open. See task-catalog-runtime-verification.md.

T12 TDD Core bulk gate/projections and model serial/control/move/selection/reset/cancel/unknown tests, then checkbox toolbar/dialog/summary en-ja UI, offscreen tests/review/full regressions/signed build. Compare source statuses/limits/partial selection policies. No live operations or VM/UI acceptance in this software phase; archive remains next.

T12 checkpoint: ff6c682→b0d234f CoreGREEN3;3113fcf→918340e modelGREEN8;ab4979c queuedcancel runtimeRED→fixed;53f5ba2 UIRED→final13Mac+3Core cases. Full427Swift (426pass/1existingAXskip),62Python pass. Model88.56%/UI43.75%lines (visible actions not accepted); signed32en-ja keys/placeholder parity pass, reviewed. Main selection/control/move/serialdelete wiring implemented; pagination/archive/restore/live task/actual UI/full21/cloud/kernel/release remain open. See tasks-bulk-verification.md.

T13 RED/GREEN archive record/service/query/batch/labels tests including valid reordered partial receipts, large IDs/raw Unicode, pagination/query encoding, statuses/owners/bounds and cancellation; review/full regression/signed catalog checks. Backend/model only: no UI design/Lazyweb. Do not claim archive feature complete before native workspace/UI/runtime comparison.

T13 checkpoint:93739acRED→90dea30GREEN8; da81515Unicode count collision runtimeRED3assertions→b5e2647GREEN9→final10. Full437Swift(436pass/1existingAXskip),62Python pass. Service/semantics100%,models95%,rawcounts98.46%lines.35en-ja package keys/strict signature/build pass, reviewed.202queued/permuted batch/byte keys/query/cancel verified; no archive feature completion. Workspace/polling/pending404/UI/bulk/livejobs/durability/full21/cloud/kernel/release remain open. See tasks-archive-core-verification.md.

T14 archive state requirements: retained paginated/search/state reads, page-local checkbox selection, single-flight two-second polling, selected-detail ownership, and accepted-restore identity reconciliation. Only a detail404 for a captured accepted restore may notify live-task refresh; page disappearance, unrelated404, failed reads and stale sessions cannot. Stop retains pending receipts; authentication reset clears them. Native tabs/actions/runtime parity remain subsequent gates.
TDD controlled stale-list/detail/reset/stop/cancel/polling and404 ownership before implementation; review, full regression, signed build and exact-head CI.

T14 checkpoint:13Core+2Mac new cases; full452Swift(451pass/1existingAXskip),62Python pass; store97.83%lines/89.23%regions, signedbuild/strictsignature and catalog/baseline checks pass, reviewed. Read ownership/polling/accepted404 and retained screen lifecycle implemented; native archive views/actions/sharedgate/livejobs/browser/full21/cloud/kernel/release remain open. See tasks-archive-state-verification.md.

T15 archive action requirements: capture explicit single/batch archive, restore, permanent delete and failed-state retry contexts; share exclusion with TaskStore category/bulk/ordinary operations and archive reads.202means accepted only, no optimistic deletion/restoration. Reordered partial batch receipts remain per-ID, never auto retry uncertainty. Capture unknown task/archive identity sets with explicit acknowledgement; cancellation/reset/stop must not unlock in-flight writes prematurely. Native UI and real-job/browser acceptance remain required.
TDD gates first, then captured action model and screen integration; controlled held-write/cancel/reset/partial/identity/limits tests; review/full regressions/build/CI.

T15 checkpoint:3Core gate+13action+1screen added; full469Swift(468pass/1existingAXskip),62Python pass. Action97.35%lines, store98.04%; reviewed shared gates/context/suspend/reset/unknown/partial/receipt callbacks, signedbuild/strictsignature/catalog/baseline pass. Native controls/tabs/dialogs, actual jobs/durability/browser/en-ja/AX comparison/full21/cloud/kernel/Docker-free release remain open. See tasks-archive-actions-verification.md.

T16 archive UI requirements: native live/archived tabs, server search/state/page20 with10/20/50sizes, page checkbox selection, nine reference columns, typed progress/error/warning summaries, restore/delete/retry per-row and bulk, captured confirmations with permanent-delete totals, en/ja outcomes and unknown acknowledgement.202is queue acceptance only. Restore reconciliation triggers live data refresh; tab/read lifecycle survives locale/sidebar and resets on logout. Real keyboard/AX/visual/runtime parity remains required after unlock.
TDD view bindings/presentation/pagination/locale and polling ownership; implement controls then offscreen en-ja hosting, reviewer, full regressions/signed resources/CI.

T16 checkpoint:13UI cases; full482Swift(481pass/1existingAXskip),62Python pass;44en-ja packaged keys/strict signature/build pass, reviewed. Native archive tabs/table/search/filter/pager/selection/confirmations/results and live actions wired; two refresh races reproduced/repaired with owned read revisions and gate-aware coalescing. Actual UI/AX/keyboard/browser and VM jobs/durability/full21/cloud/kernel/Docker-free/release remain open. See tasks-archive-ui-verification.md.

T17 archive runtime requirements: fresh disposable state only, fixed terminal tasks and exact synthetic bytes seeded without normal createTask/launchTask, bounded native API archive/restore/delete checks versus pinned reference, same-disk restart durability, no live profiles/LLM/agents/host commands. Split prerequisite fixture boundary verification (T17a) from actual VM/reference operations (T17b); neither alone closes runtime acceptance. Preserve failed experiments; never promote kernel candidate by a single run.
T17a TDD host/UID/arch/marker/DSN/fresh-state/no-clobber guards and exact seed proof; review/full regressions/build/CI before any VM mutation. T17b follows dedicated reviewed exercise/probe/reference plan and hardware runs.

T17a checkpoint:7newPython cases, final69Python pass;482Swift(481pass/1existingAXskip), signedbuild/strictsignature/catalog/baseline pass. Actual isolated PostgreSQL nkey RED/rollback ->fixed2terminaltasks+3files/1056bytes exactreadback/replay rejection; no ARTEX/VM started, owned containers removed/original4unchanged, reviewed. T17b finite exercise/probe/reference and3boot jobs/durability plus UI/full21/cloud/kernel/release remain open. See task-archive-seed-verification.md.

T17b Core exercise contract: required guest-only fixture control for quarantine/repair of the ready archive for fixed task7101 plus zero-agent audit; bounded120polls/45sec stage budget, no automatic write retry. Phase2 proves initial terminal rows/files, bulk archive, deliberate restore_failed then explicit retry, restored exact metadata/files, second delete and first rearchive checkpoint. Phase3 consumes same-disk checkpoint and proves persisted ready archive and final restore/files/second deletion. Injectable clock/sleep and fake fault control are unit-test dependencies, not runtime evidence. Probe/reference/hardware integration still required.
TDD finite allowed paths/status/poll/cancel/identity/bytes/checkpoint/report completeness first; code review/full regressions/build/CI before actual jobs.

T17b runtime checkpoint: native3boots/same disk/retained session/19archive checks/3exact files/3cooperative stops plus full stopped-log audits pass. Independent e75 binary reference3backend starts exactly matches normalized exercise and bytes; final reference cleanup/log export/original4browser guards pass. Full501Swift (500pass/1existingAXskip),84Python;96.15%exercise and95.95%client lines. Failed reference preparation/null-page/log-copy attempts retained. Signed build-only passes. See task-archive-runtime-verification.md and normalized t17b evidence. This archive backend/restart gate is complete; UI/full21/cloud/kernel reliability/clean-Mac/release gates remain open.

F1 order: source contract/checksum fixture and tests -> executed missing-API RED commit -> models/query/service GREEN -> reviewer identity/null/Unicode/partial-patch checks -> independent browser filter oracle -> full regressions/coverage/signed build/exact-head CI. F2 state/F3 UI/F4 runtime/F5 advanced workflows remain open.

F1 checkpoint: typed finite Findings list/group/tree/stats/task/detail/update/delete contracts implemented;16focused cases,8executed pinned browser filter projections. Full517Swift (516pass/1existingAXskip),86Python pass; models98.67%/aggregates98.72%/service99.23%lines. Native soft-tree-budget runtimeRED e53b981 ->2fdd717 fixed; review and signed build-only/resource checks pass. Findings remains pending. See findings-core-verification.md. F2 state, F3 UI, F4 actual VM/reference, F5 advanced workflows and full21/cloud/kernel/release remain open.

F2: missing slot/store API RED; read/page ownership GREEN; store query/group/tree/detail/selection controlled tests; captured mutation/uncertainty/reset/cancellation RED/GREEN; independent polling tests; review/full regressions/coverage/signed build/exact-head CI. F3 UI/F4 actual VM and complete Findings/full21 remain open.

F2 checkpoint: owned Findings read/page/store, separate5sec view/stats loops and one-shot asset snapshots, cross-page selection, captured edit/delete confirmations and conservative unknown outcomes implemented.33focused cases (6read/10store/10mutation/7poll); full550Swift (549pass/1existingAXskip),86Python pass. Read/poll100%, store98.03%, mutation98.77%lines. Five executed unit-regression groups preserve independent stats/cancelled cursors, contextual provenance/ack episodes, gated/cancelled asset work and scope/page tree independence. Review and signed build-only/baseline checks pass; Findings stays pending. See findings-state-verification.md. Next F3 native en/ja controls/preferences and actual UI after unlock; F4 actual VM/reference and F5 advanced features/full21/cloud/kernel/clean-Mac/release remain open.


F3.1 order: requirements/design -> missing coordinator RED -> bounded preferences and captured dialog GREEN -> stale owner/held mutation/unknown episode/Unicode tests -> review/full regressions/signed build/exact-head CI. F3.2 controls and F4/F5 remain open.


F3.1 checkpoint: captured edit/status/delete/uncertainty contexts and bounded browser-equivalent preferences implemented. Missing API RED cd266a7; reviewer draft-loss regression RED81db173 (3 assertions) -> f503a45 GREEN13. Full563Swift (562pass/1existingAXskip),86Python pass; screen92.17%/preferences100%lines; signed build-only, strict signature, localization/baseline checks and read-only re-review pass. Findings remains pending. Next F3.2 native en/ja controls/presentation/RootView retention/read scheduling/offscreen tests; actual UI after manual unlock, F4/F5/full21/cloud/kernel/clean-Mac/release remain open.


F3.2 order: document requirements/design -> missing bindings/presentation/read-coordinator RED -> native controls and en/ja catalog GREEN -> held tree/scope/page latest-read and mutation gate tests -> offscreen en/ja light/dark wide/narrow hosting -> review/fix/full regression/signed build/exact-head CI. Actual unlocked native/browser/keyboard/AX and F4/F5 remain required.


F3.2 checkpoint: native three-view Findings workspace, six stats, filters/pagers/selection, detail/provenance and captured triage/delete/unknown dialogs connected to RootView; mirrored feature statusin_progress. REDf140c0e APIs; RED9d8ad0f polling1assertion; RED73091e3 callbacks3cases/5assertions -> GREEN081ec24. Full578Swift(577pass/1existingAXskip),86Python pass;15UI+13screen cases;61en/ja packaged keys, strict signed build-only and frozen baseline pass. Reads/presentation100%, model93.84%, bindings97.67%; table62.60% explicitly retains real row interaction gate. Static re-review pass. Actual UI/keyboard/AX/manualunlock, F4 VM/reference, F5 advanced/full21/cloud/kernel/clean-Mac/release remain open.


F4a order: requirements/design -> missing seed RED ->33fixed findings/11terminal tasks + strict runtime/DSN/emptyDB/SQL/child timeout controls GREEN -> Python/security review -> actual complete pinned PostgreSQL rollback/readback/replay proof -> full regressions/build/CI. Then F4b finite native probe/reference/actualVM and F5 advanced; actual UI after unlock remains required.


F4a checkpoint: missingseedRED6dcad07; sequenceunitREDeac81de -> fixed6b19cc9. Nine seed cases/95Python pass;578Swift(577pass/1existingAXskip);101/102seedlines99.02%. Actual PG16.15 old/fixed forcedfinal-error proof isolates six nontransactional sequences, repaired rollback of rows+sequences,33exactfindings/31nodepayloads/legacy/11terminaltasks/inherit/33triggerlinks, main+SQLreplay refusal and zeroactivity. Two preparation failures retained, owncontainers/derivedtagremoved/original4unchanged; Python/security/report review and signedbuild/strictsignature/resource/baseline checks pass. No ARTEX/VM/UI acceptance or kernel promotion. Next F4b finite native/reference exercise/probe and actual same-disk operations; F3visibleafterunlock/F5/full21/cloud/kernel/clean-Mac/release remain open.


F4b order: inspect pinned service/notification/node-sync contracts -> write Core fixture vectors/request bounds/checkpoint tests RED -> typed finite exercise GREEN -> DEBUG seed/audit/probe and independent reference with guardtests -> review/full regressions/build/CI -> actual three-boot dedicatedVM and separate pinned backend starts -> normalized compare/full stopped-log audit/cleanup -> evidence. Do not mark F4 accepted from Core unit/fake output; actual partialPATCH/durability/UI/full21 remain required.


Generated unassigned-asset label: missing presentation API RED, implement sentinel-scoped translation GREEN, raw/custom Unicode preservation test; reuse all Findings UI tests/review and packaged en/ja resource check. Actual visible language/AX remains after unlock.


F4b foundation checkpoint: finite transport, checksum-bound independent dataset, full row verifier and single-use43list/33detail read stage implemented.17 focused Core cases and16 Findings UI cases pass. Full596Swift (595pass/1existingAXskip),95Python pass. This remains a partial F4b implementation: aggregate/context/mutation/probe/reference/actual three-boot stages are required. See findings-runtime-foundation-verification.md.


F4b CI repair order: preserve failed run40466516578/head184adac as compile RED -> typed test helper -> focused/full tests -> review -> exact-head CI. No scope reduction or job suppression.


Expanded-read sequence: missing aggregate/context API RED -> typed verifier GREEN -> wire/negative mutation checks -> bounded read-stage integration -> review/full checks -> DEBUG probe/reference and real three-boot comparison. Never infer backend success from generated expected JSON.


Reference order: missing pure client/verifier RED -> independent guards/filters/row/aggregate/context GREEN -> source/security review -> fresh offline image from cached pinned inputs -> actual3starts -> canonical compare against stopped native3boot report -> export logs/dump then cleanup owned reference only. Full visible UI and kernel reliability gates remain open.


F4b actual checkpoint: native73ac82a completed3same-disk boots with116/100Findings requests; independent reference20b915b completed3backend starts with matching shared projection and source/binary/seed/audit binding. First reference network preflight failure is retained, corrected run exported state/logs and cleaned only owned resources. Full616Swift (615pass/1existingAXskip),120Python. Individual name/class/severity requests and extra boundary/normalization cases remain F4b work; actual UI after unlock, F5/all21/cloud/kernel/clean-Mac/release remain open. See findings-runtime-verification.md.


Boundary order: missing stage RED -> seven-request typed stage and three no-dispatch validation checks GREEN -> schema2 outer/probe/reference/comparator integration -> independent review/full regressions -> actual fresh3boot VM +3start isolated reference -> source-bound compare/cleanup evidence/build/exact-head CI. Do not overwrite schema1 actual reports or promote the kernel.

Boundary checkpoint: native5983949 three boots and independent referencea4689b2 three starts pass schema2/123pre-restart/100persisted reads; single-field/normalization/empty/8192byte/restoration assertions match. First reference empty-name omission failure retained, focused RED/GREEN and new disposable actual pass. Full620Swift(619pass/1existingAXskip),123Python; outer/boundary lines100%, signedbuild/strictsignature/localization/inventory pass. See findings-boundary-verification.md. Actual UI after manual unlock and F5/all21/cloud/kernel/clean-Mac/release remain open.


F5 order: requirements/design -> source-bound traffic fixture and missing read APIs RED -> typed read contracts/service GREEN -> adversarial identity/byte-page/cancellation checks -> independent review/full regression/coverage/signed build/exact-head CI. Then evidence mutations/state, lineage/retest/deepen/report, full-byte exports, UI and actual fixed-browser/VM comparisons. F5a alone does not accept F5.


F5a read contract checkpoint: RED7fa5bae -> GREEN718e5cc; six traffic tests, full626Swift(625pass/1existingAXskip),123Python. Model54/54 and service32/32 lines covered; review feedback strengthens size/status tests, signed build/strict signature/localization/inventory pass. See findings-traffic-read-verification.md. Actual nonempty traffic/API/state/UI and remaining F5/full-product gates stay open.


F5b order: pinned mutation/transaction/readback investigation -> write capability missing-API RED -> four command contracts GREEN -> adversarial membership/body/version/cancel/status tests -> independent review/full software checks. Then owned state with reverse replies/stop/reset/uncertainty/ack/conflict tests -> actual nonempty evidence and native UI. Preserve F5a pending CI40536321956 until authoritative terminal state.


F5a CI40536321956 exact2fdfc40 success. F5b write capability: missingRED10fdc5e -> review regressionREDb6cf82d -> corrected9549cae. Focused10, full630Swift(629pass/1existingAXskip),123Python; service90/90/model54/54 lines; signed build/strict signature/localization/inventory pass. State ownership/unknown/ack/stop/reset/detail/body still required before UI, plus actual nonempty evidence and remaining F5/full-product gates. See findings-traffic-write-verification.md.


Traffic state order: missing store RED -> controlled reverse/held read and write fixtures -> owned summary/detail/body plus uncertainty/ack/stop/reset GREEN -> review/full regression/coverage/signed build/exact-head CI. F5 actual nonempty evidence and UI remain open.


Traffic state checkpoint: missingREDdedfcb2 -> handoffRED21439be(11cases/5assertionfailures) -> GREENee62d39. Focused21, full641Swift(640pass/1existingAXskip),123Python, state161/163/sharedread50/50/service93/93 lines, signedbuild/strictsignature/localization/inventory pass. See findings-traffic-state-verification.md. Next explicit recurrence audit: reproduce prepare/handoff in existing FindingStore/other mutation stores with Observation before UI integration. Actual nonempty traffic, native controls, F5/full-product remain pending.


Recurrence audit order: ordinary FindingStore edit/delete Observation RED -> internal handoff callback/ticket-derived busy GREEN -> existing mutation/read/UI/probe regression and review -> full software checks/CI. Then TaskStore/LLM triage and native evidence controls; no full-product completion claim.


Ordinary FindingStore recurrence checkpoint: RED3b0e6f3(12cases/10assertionfailures) -> repair1108f91, focused39/full643Swift(642pass/1existingAXskip),123Python; mutation104/105/service140/140/store200/203 lines; signedbuild/strictsignature/localization/inventory pass. See findings-mutation-handoff-verification.md. Next TaskStore direct/external and LLMStore handoff audit, then native evidence controls/actual nonempty guest/browser/UI. Full goal remains open.


Task handoff order: five direct/two synchronous boundary modes and three external acquisition kinds RED -> ticket/callback/lease GREEN -> existing service/store/workspace regression -> independent review/full checks/CI. Do not launch guest agents during these synthetic tests.


Task preparation checkpoint: RED89bda84(4tests/37assertionfailures) ->51f3370, focused31/full647Swift(646pass/1existingAXskip),123Python, TaskStore229/229 and TaskService80/80 lines. Independent review/signedbuild/strictsignature/localization/inventory pass. See task-mutation-handoff-verification.md. External post-grant workspace dispatch and LLMStore audit remain, followed by evidence UI/actual nonempty guest/browser/full-product gates.


External handoff order: synchronous workspace suspend/live-stop/cold-stop RED -> one-request marker/lease validation -> typed services/controllers GREEN -> existing and full tests/review/build/CI. LLM and actual evidence/UI gates remain open.


External post-grant checkpoint: RED6711a05(44workspace/10assertionfailures) ->4853bf3, expanded83/full654Swift(653pass/1existingAXskip),123Python; independent review/signedbuild/strictsignature/localization/inventory pass. See task-external-handoff-verification.md. Category/bulk/archive source and controlled handoff audit covered; actual guest/UI acceptance and LLMStore audit remain, then evidence UI and remaining F5/all21/cloud/kernel/clean-Mac/release.

LLM transport cancellation order: requirements/design in llm-transport-cancellation-design.md -> pre/post-cancel and finite-JSON RED -> shared service boundary GREEN -> independent review/full regression/coverage/signed build/CI. This checkpoint does not resolve LLMStore handoff/unknown-result recovery or editor lifecycle ownership. Actual native/browser comparison, evidence UI and all remaining product gates stay open.

LLM recovery checkpoint: missingAPI REDdb2de38 -> initial28 GREENc16fd45 -> stale-review/recursive-stop RED6b3a35c and localization RED3c84608 ->36 GREEN89f6728 -> reviewer resume RED3e903fb(2cases/3assertions) ->38 GREEN2088822 -> navigation-owner missingAPI RED4210528 ->41focused GREENfb106b1. Recovery requires settled write, full read and explicit current revision acknowledgement, with a retained same-session window store and three bilingual panels. Complete full regression/sign/build/CI; real UI/guest acceptance, probe/editor lifetime and crash/restart uncertainty are still pending, plus all broader F5/full-product gates.

Final recovery software check: window ownershipfb106b1 + offscreen525c9c8,42focused/full680Swift(679pass/1existingAXskip),123Python; service131/133/store172/173/coordinator13/13/panel207/210 lines. See llm-mutation-recovery-verification.md. Preserve actual UI/guest/probe lifetime/durable uncertainty and all broader product gates.

LLM editor lifecycle: missing-owner RED1700475 ->6 GREEN85bc270 -> expanded RED19dd23b(15cases/6assertions) -> parent activity and credential restoration repair3110030(57focused) -> sole-draft-owner/offscreen333302b(59focused). Full697Swift(696pass/1existingAXskip),123Python; model120/122/view391/430/store173/174 lines. See llm-editor-lifecycle-verification.md. Owner, cancellation, revisions and forced-disappearance software checks are covered; external sheet/picker/browser/guest/provider acceptance, process-restart uncertainty and all broader product gates remain pending.

F5c full traffic UI inventory is now in findings-traffic-ui-design.md, including picker paging/filters/selection/raw preview, roles/notes/order/remove, byte previews and full-byte downloads. Missing candidate APIs RED e33e7b6 ->67e9be8:8contract/29related tests; full705Swift(704pass/1existingAXskip),123Python, DTO55/55/service20/20 lines. See captured-traffic-verification.md. Next required steps are owned picker/preview and parent integration, authenticated full-byte export, all native controls, actual guest/browser/nonempty/persistence and unlocked UI acceptance. Read API success does not close F5 or any whole-workflow gate.

F5c1 remote gate: CI40637957743/92ae187 stopped before tests due GitHub account payments/spending-limit settings. Account-owner action is required; do not rerun unchanged work until that external condition changes or call CI passed. Continue owned picker/preview and export implementation using local checks; full goal remains active with this extra CI gate.

F5c2 state: missingRED e1ba09a -> read-acquisition REDb1f4d5f(14cases/7assertions) -> GREENfe8d687 -> publication/lifecycle REDca191b7(21cases/8assertions) -> GREENed3f6b7.21 owner cases/50related/full726Swift(725pass/1existingAXskip),123Python; picker206/208/sharedread56/56/parent168/170 lines. See captured-picker-verification.md. Next: window/detail/picker/viewer controls and authenticated full-byte export, then actual nonempty guest/browser and unlocked UI/AX. CI account gate and all full-product requirements remain open.

Changed-code CI40640261823/e34c325 remains account-blocked before testing, confirmed by job/check annotations. Local checks pass; remote CI is still unverified. Continue full-byte export/native integration without treating this infrastructure condition as full-goal completion or an impasse while useful implementation remains.

## Investigation harness roadmap (not implemented)

See investigation-harness-design.md and investigation-harness-design.ja.md.

- [ ] H0: adapter contracts, scope enforcement, pinned build/license inventory and isolated fixtures.
- [ ] H1: Dirsearch actual lab runs, results/evidence, cancellation and persistence.
- [ ] H2: Fscan discovery and explicitly selected checks with expected lab inventory.
- [ ] H3: Masscan raw-network/capability experiment, accuracy/rate/negative egress proof.
- [ ] H4: SoftEther Stable/Developer comparison and isolated VPN lifecycle/leak tests.
- [ ] H5: en/ja native UI, browser parity for shared workflows, accessibility and packaging.

Existing full-byte export and browser parity work retain their current priority. No tools have been installed or scans run for this proposal.

## F5d2 evidence export connection

- [x] RED: authenticated staging/current commit, stale/401/cancel/VM/UI ownership and concrete stopped-client tests using actual files.
- [x] GREEN: receipt ownership, typed transport/client and registered VM transfer with evidence lifetime epoch.
- [x] Local review/full regression/coverage, guest artifact tests and signed build. Hosted CI remains unverified due exhausted account quota; see evidence-export-connection-verification.md.
- [ ] Actual guest transfer/VM-stop comparisons and full native save controls remain required beyond this software checkpoint.

F5d2 software checkpoint:36focused/755Swift(754pass/1existingAXskip)/123Python; actual129MiB+17 streamed disk proof, receipt/auth/manifest100%lines, stopped-only VM coverage52/472 explicitly leaves actual vsock/stop/restart gates open. See evidence-export-connection-verification.md and its Japanese counterpart. During exhausted Actions quota, all our push HEADs use [skip ci]; no remote CI or billing changes.

## F5d runtime acceptance

- [x] R1 fixed diagnostic bodies, full streaming audit and environment/file/SQL negative tests (14 cases plus actual guest execution).
- [x] R2 typed DEBUG fixture client and bounded proofs (3 cases and both native experiments).
- [x] R3 fresh signed zero-NIC VM original-body export, witnessed caller cancellation/live VM stop, receipt stop/restart and persistence proof.
- [ ] R3/R4 detailed preview content/binary/truncation comparison; metadata reads alone are insufficient.
- [x] R4 independent pinned reference exact-byte comparison for original body downloads only.
- [ ] R5 full native controls and unlocked UI acceptance.

See evidence-export-runtime-design.md and evidence-export-runtime-design.ja.md.

F5d runtime: initial be693f7 and final9b41048 experiments each exited0/two boots; four complete bodies per boot incl135266321 bytes. Final caller237320/VMstop696832 staged bytes; operation-specific interrupted socket proof and VMstop count1; no final/partial files after cancellation, persisted downloads match.767Swift(766pass/1existingAXskip),137Python, release diagnostic exclusion and signed app checks pass locally. See evidence-export-runtime-verification.md and Japanese counterpart. Browser/API exact comparison, full F5 controls/UI and all full-product gates remain open. All our push HEADs still use [skip ci].

F5 remaining integration gates also include nonempty captured-traffic bind/edit/remove/reorder, actual conflict/unknown-outcome behavior and persistence against both guest and pinned reference. The original-body SQL fixture does not populate disposable captured traffic and does not prove those mutation/picker gates.

## F5d independent reference

- [x] BR1 independent bounded HTTP/body verifier and error-path tests.
- [x] BR2 two-start fixed reference fixture, persisted full downloads and activity/isolation audits.
- [x] BR3 private export of eight response files, byte-for-byte native comparison and owned cleanup.
- [ ] BR4 detailed preview/captured mutation/UI/full product acceptance remains open.

See evidence-reference-design.md and evidence-reference-design.ja.md.

## Four cloud providers (new user goal; not implemented)

- [ ] CP1 provider identity, wire-format/capability and backwards-compatible persistence contracts.
- [ ] CP2 guest model discovery/stream/tool adapters and mock error/cancellation/signature tests.
- [ ] CP3 isolated egress and actual minimal four-provider verification with app-entered keys.
- [ ] CP4 en/ja native controls, keyboard/VoiceOver and shared browser comparisons.

See cloud-providers-design.md and cloud-providers-design.ja.md. Keep current original-body comparison/export work moving; do not enable cloud egress just by adding this goal.

Independent reference checkpoint: attempt1 exited1 at tmpfs export with complete owned cleanup; attempt2 at8accf4f exited0 and compared eight full response files against actual native outputs.18 focused/155 full Python tests pass. Detailed preview, captured mutations, native UI and full product gates remain open. See evidence-reference-verification.md and Japanese counterpart. Four-provider CP1–CP4 remain planned.

## F5e native evidence controls

- [x] E1 owned read/view/save workspace and parent lifecycle, typed original-body export connection.
- [x] E2 binding metadata, raw headers/body tabs, explicit cumulative pages, binary feedback and actual-window Save Panel implementation; bilingual labels.
- [x] E3 software negative tests/review/regression/coverage and offscreen locale/theme construction. See findings-traffic-ui-verification.md and Japanese counterpart.
- [ ] E4 actual managed-guest new UI/save-panel run and detailed preview/original-body browser comparison.
- [ ] E5 captured picker plus role/note/remove/reorder controls, conflict/unknown outcomes and nonempty actual persistence comparison.
- [ ] E6 unlocked visual/keyboard/VoiceOver/multiwindow and all full-product release gates.

F5e software checkpoint:22 new workspace/51 related/789 full Swift (788 pass,one existing externalAX skip),155 Python. Real temporary-file tests cover publication and cancellation; actual new UI/VM/panel acceptance remains open. Gemini/Groq CP1–CP4 and investigation harness H0–H5 remain planned. Hosted CI is unverified; our publication HEAD uses [skip ci].

## F5e2 evidence mutations and retained recovery

- [x] M1 captured role/note/remove/adjacent-order dialogs and immutable version/membership/draft bindings.
- [x] M2 retained window store, pending/unknown parent gate, target/context recovery, explicit acknowledgment and confirmed finding/report refresh.
- [x] M3 scoped old-sheet/old-session teardown and byte-preserving note/Unix-second parity regressions; review and local full checks.
- [x] M4 native captured picker/add UI and its selection/filter/page/raw-preview controls (software checkpoint; subsequent M5 runtime passed, M6 remains open).
- [x] M5 real nonempty guest/reference mutation effects, conflict/unknown outcomes and restart persistence. (Typed runtime comparison; actual UI remains separate.)
- [ ] M6 detailed preview/binary/truncation, actual panel, unlocked visual/keyboard/VoiceOver/multiwindow and all original release gates.

Historical checkpoint (typed runtime superseded by F5e5 below):14 action +23 workspace/77 related/804 full Swift (803 pass,one existing externalAX skip),155 Python. See findings-traffic-mutations-design and findings-traffic-mutations-verification in en/ja, plus bugs/evidence-mutations. Previous F5e E5 remains open because its picker and real-runtime acceptance are not complete. Four-provider CP1–CP4 and harness H0–H5 remain planned. Full goal stays active; hosted CI remains unverified and our push HEAD uses [skip ci].


## F5e3 captured picker connection

- [x] P1 byte-based draft tickets,250ms cancellation, query/page/selection/preview identity and parent modal gates.
- [x] P2 EN/JA candidate filters/table/selection/page/raw tabs/add controls, disabled-history/unavailable/empty/error/loading feedback.
- [x] P3 confirmed metadata callback, uncertain-write retention, scoped close/busy/reentry fixes, review/full regression/coverage.
- [x] P4 actual managed-guest/frozen-reference nonempty captured-index operations, conflicts/unknown outcomes and restart persistence. (Typed runtime comparison; actual UI remains separate.)
- [ ] P5 detailed preview/binary/truncation/download and unlocked mouse/keyboard/VoiceOver/save-panel/multiwindow/screenshots.

Historical F5e3 software checkpoint (typed runtime superseded by F5e5 below):20 new picker cases,824 full Swift (823 pass,one existing externalAX skip),155 Python. See captured-picker-ui-design/verification and bugs/captured-picker-ui in en/ja. F5's actual runtime/visual/full-workflow gates remain open. CP1–CP4 and H0–H5 remain planned; no full goal completion or hosted CI success is claimed. Our pushed HEAD uses [skip ci].

## F5e4 actual captured-index reference runtime

- [x] R1 guarded loopback fixture generates29 real recorded exchanges; fixed body/source oracle and bounded shutdown.
- [x] R2 independent reference exact pages/filters/source identities, bindings/edit/order/remove/409 and original-body previews; two backend starts persist.
- [x] R3 frozen executed-source hashes, parent-tag checks before cleanup, repeat equality and local171 Python tests; sanitized receipt and bilingual RCA.
- [x] R4 rebuild capture-enabled native image with proven candidate kernel; typed native comparison, two VM boots, uncertainty recovery. (Typed runtime comparison; actual UI remains separate.)
- [ ] R5 actual new UI/browser/keyboard/AX/multiwindow/save-panel and binary display localization acceptance.

See captured-runtime-verification.md and Japanese counterpart. Reference-only success does not close P4/M5/E4/E5 or any full-product gate. CP1–CP4 and H0–H5 stay planned. Hosted CI is unverified; pushed HEAD uses [skip ci].

Historical R4 partial checkpoint (superseded by F5e5 below): fresh capture-configured candidate image built offline; signed DEBUG --evidence-export exited0 across two actual CPU1 VZ boots, retaining the prior four-body export/persistence/interruption checks. No default promotion or app replacement. Actual recorder API/nonempty typed native capture mutations and unknown outcomes remain unverified, so R4/P4/M5/E4/E5 stay open. See captured-native-candidate.json and captured-runtime-verification in en/ja.

## F5e5 native recorded-index comparison

- [x] N1 fixed readonly native index guard, actual loopback generation, live WAL and executed-source proof.
- [x] N2 actual typed capture service/picker/store pages/filters/selection/raw preview, originals/bounded previews, bind/edit/order/remove and409.
- [x] N3 controlled withheld-response unknown gate/readback/explicit acknowledgment without retry; two fresh experiments, two VZ boots each, exact normalized reference equality and persisted29-record/final binding state.
- [x] N4 full832 Swift (831 pass,one existing external AX skip),179 Python, scoped unit+real-native coverage/review, release diagnostic rejection and baseline/localization checks.
- [ ] N5 actual new UI/browser/mouse/keyboard/VoiceOver/multiwindow/save-panel and typed binary display localization acceptance.

See captured-native-verification.md/.ja.md, bugs/captured-native.md/.ja.md, captured-picker-reference.json and captured-native-comparison.json. Native runtime closes M5/P4/R4 only; E4/E5 UI acceptance, M6/P5/R5, all21 workflow/release/kernel goals, CP1–CP4 and H0–H5 remain open. Default profile and installed app were not replaced. Hosted CI stays unverified; publication uses [skip ci].

## F5e6 typed binary notice localization

- [x] B1 preserve raw cumulative/API content and headers; display only nonbinary text pages under the existing EN/JA notice.
- [x] B2 initial/later binary, ordinary identical marker/CJK/FEFF/NFD, rejected append and both-side locale/offscreen/no-request tests.
- [x] B3 full837 Swift (836 pass,one existing AX skip),179 Python, changed-file combined line86.43%, review/localization/baseline; local staged app rebuilt/strict signed with prior guest profile retained.
- [ ] B4 actual new UI/browser/keyboard/VoiceOver/multiwindow/save-panel comparison; untyped raw-marker audit without packet rewriting and all broader product gates.

See evidence-binary-localization-design/verification and bugs/evidence-binary-localization in en/ja, plus binary-localization-verification.json. N5/P5/M6/R5 remain open: typed localization software is fixed, actual UI acceptance is not completed. CP1–CP4/H0–H5 and full21 workflow/kernel/release requirements continue. Hosted CI is unverified; pushed HEAD uses [skip ci].

## Standalone Traffic workflow

- [x] TR1 full-filter/sort/query, host/proxy/null/precision contracts and fixed finite read/delete/capture-setting boundaries with adversarial tests (finite API foundation only).
- [x] TR2 window-owned reads/selections/confirmation scopes, unknown-write recovery and reentry/stop/session lifecycle (state-only checkpoint).
- [ ] TR3 full EN/JA native traffic controls, raw detail, flow-to-finding binding, blob originals and page0 polling, with Lazyweb first.
- [ ] TR4 actual multi-host VM/reference comparison, exact/substr/purge effects, bound evidence persistence, blob bytes, capture settings and restart.
- [ ] TR5 actual browser/native UI/keyboard/VoiceOver/multiwindow and full release gates.

See traffic-workflow-design in en/ja. Traffic remains pending in the feature map until real native controls exist; finite contracts do not close this workflow. Earlier Findings advanced lineage/retest/deepen/report and existing visual/kernel/provider/harness gates remain open.

TR1 checkpoint:12newTraffic +8existingcaptured cases pass; full849Swift (848pass,oneexistingAXskip),179Python; affected core172/172LLVM lines. FEFF runtime oracle failures were corrected using raw percent bytes/typed JSON without production normalization. Staged app rebuilt/strict signed with previous guest hashes retained; no new screen, actual server mutation, candidate promotion or workflow acceptance. See traffic-service-verification en/ja, bugs/traffic-service-foundation en/ja and evidence/traffic/finite-verification.json.

TR2 checkpoint:21 new state cases; full870Swift (869pass,oneexistingAXskip),179Python; TrafficStore357/358 and prepared TrafficService64/64LLVM lines. Reset-query/unavailable-recovery and busy-release departure failures are retained with RED/GREEN history. Local staged app rebuilt/strict signed with old guest hashes; no new Traffic screen, real deletion, polling task or durable cross-window/process uncertainty journal. See traffic-state-design/verification and bugs/traffic-state en/ja plus evidence/traffic/state-verification.json. TR3–TR5 and all original broader gates remain open; hostedCIunverified, pushedHEAD[skip ci].

TR3 input preparation: the native input reducer now covers independent byte/revision/presentation tickets, ECMAScript trimming, per-field proposals, advanced reset, browser page sizes/status/sort and Linux64 numeric filtering. Transactional proposals must be adopted only after synchronous TrafficStore acceptance; rejected inputs and pending sibling drafts are tested. See traffic-filter-input-design in en/ja. This is no screen/timer/polling implementation: TR3 stays open, feature-map pending, all binding/export/real VM/browser/EN-JA/keyboard/AX/kernel/provider/harness/release gates remain unchanged.

TR3 input receipt:17 new input cases, full887Swift (886pass/oneexistingAXskip),179Python after resolving the command-local missing Node PATH; reducer97/98LLVM lines. Local staged app rebuilt/strict signed with previous guest hashes retained. See traffic-filter-input-verification en/ja, bugs/traffic-filter-input and evidence/traffic/filter-input-verification.json. No new screen/timer/VM effect or workflow completion; hostedCIunverified, pushedHEAD[skip ci].

TR3 presentation/read model: compose independent300ms filter jobs and page0-only5s polling with current-query proposals, immutable presentation leases, fresh adjacent paging and owned reads. Actual boundary RED ada08e1 reproduced lost matured drafts and ignored teardown resets; e5fc56f repairs both with a gate-release queue and reset priority. Root attachment/actual screen remains open; no backend mutation is initiated by the model, feature-map stays pending. See traffic-screen-model-design and bugs/traffic-screen-model in en/ja. Keep full TR3–TR5 and original goals unchanged.

TR3 model receipt:18 new model cases; full905Swift (904pass/oneexistingAXskip),179Python; model239/240LLVM attributed entries and171/171unique physical LCOV mappings (different Observation-generated mapping denominators). Signed staged app rebuilt with previous guest hashes. See traffic-screen-model-verification en/ja, bugs/traffic-screen-model and screen-model-verification.json. Root/native UI, actual clock timing, full binding/export/VM/browser and all original gates remain open. No goal completion or hostedCI success; publication[skip ci].

TR3 partial native controls: RootView now retains a session/window-owned Traffic model; native filters/status/method/size/server sort, host counts/selection, fresh adjacent pages, raw request/response/wrap/copy and frozen substring/exact-host/purge confirmations are connected.59 owned EN/JA labels; feature-map is in_progress. Pending flow-to-finding binding, blob-original extension and sort persistence keep TR3 unchecked. Actual root/VM/browser/mouse/keyboard/AX/multiwindow and all original gates stay open.

TR3 native UI receipt:12 new UI cases; full917Swift(916pass/oneexistingAXskip),179Python, fixed22-case browser Host-function UTF8 equality, localization/baseline pass. Four Traffic files1025/1227LLVM attributed entries(83.54%); TrafficView74.23% and RootView0/337 separately disclosed. Staged app rebuilt/strict signed with previous guest hashes; not launched or installed elsewhere. See traffic-native-ui-design/verification en/ja, bugs/traffic-native-ui and evidence/traffic/native-ui-verification.json. Read-only reviews found no concrete blocker after actual acknowledgment/Host/dialog/preview REDs; hostedCI remains unverified, publication[skip ci].

TR3 next: persist only sort field/direction using disposable-suite-tested native preferences, hydrate before first read and defer behind outstanding writes. Follow traffic-sort-preference-design en/ja and TDD before implementation. Layout unchanged/Lazyweb out of scope. Full binding/blob/runtime/UI/provider/harness/release gates stay open.

TR3 sort persistence software:9 new cases cover6 valid pairs/9 invalid inputs, canonical field/direction-only native storage, accepted-only writes, privacy/reopen, stale/modal/Observation and held-write deferred hydration.02441cf compileRED→0aee4c0 one actual retired-lease assertionRED→454d398 GREEN. Full926Swift(925pass/oneexistingAXskip),179Python; preference23/24/model385/394LLVM entries, RootView0/337 separately excluded. Staged app rebuilt/strict signed with prior guest hashes. See traffic-sort-preference-verification en/ja, bugs/traffic-sort-preference and sort-preference-verification.json. Sort persistence is implemented; TR3 binding/blob, actual app-domain/root/browser/VM/UI/AX and all original gates remain open. HostedCIunverified; publication[skip ci].

TR3 binding state preparation: follow traffic-binding-state-design en/ja before UI integration. Implement a retained one-write/consumed-request core using existing fixed FindingTrafficService routes, receipt source-presence verification and explicit unknown recovery. Full250ms finding search/dialog/flow selection/parent mutation gates, blob extension, actual VM/browser/UI and all original goals remain mandatory and open.

TR3 binding core receipt:20 new cases, full946Swift(945pass/oneexistingAXskip),179Python; new TrafficBindingStore258/259LLVM attributed entries. Prepared literal refs/default role, fresh summary/complete-source receipt, consumed nonce, retained one-write/unknown recovery and publication/epoch cases pass. Initial canonical/FEFF fixture failures were corrected without relaxing production contracts; see bugs/traffic-binding-state and traffic-binding-state-verification en/ja plus evidence/traffic/binding-state-verification.json. Staged app rebuilt/strict signed with prior guest hashes. Parent/root retention, shared binding/deletion gates, matching-flow revision clearing,250ms finding search/native dialog, blob and actual VM/browser/UI/release goals remain unimplemented/open. No new linking UI or real bind; hostedCIunverified, publication[skip ci].

TR3 linking UI integration plan: follow traffic-linking-ui-design en/ja and TDD. Root-retained core, cross-page flow controls,250ms candidates/readonly targets, parent/query/flow ownership, shared bind/delete gates and explicit recovery sheet must all connect; do not close TR3 merely for rendering a dialog. Blob and all actual runtime/UI/release goals remain open.

TR3 linking UI software integration: root now injects shared authenticated services; a retained binding core, cross-page literal flow controls,250ms paged finding search, read-only candidate rules, native EN/JA dialog, matching-revision confirmed clearing and shared deletion/binding gates are connected. Explicit uncertainty recovery survives sheet closing without automatic retries/acks.21 new integration cases; full967Swift(966pass/oneexistingAXskip),179Python. Workspace163/165 and dialog273/297LLVM attributed entries; existing TrafficView618/832 and RootView0/339 remain separately disclosed. Real encoded-path overflow RED, review severity and frozen-browser finding-ID/fallback gaps were repaired with checkpoint commits. See traffic-linking-ui-design/verification and bugs/traffic-linking-ui in en/ja, plus evidence/traffic/linking-ui-verification.json. Staged app rebuilt/strict signed with unchanged prior guest hashes; no launch/install elsewhere/profile promotion. TR3 blob and actual VM/server/browser/native/root/keyboard/VoiceOver/multiwindow, full21 workflow/kernel/provider/harness/release gates remain open. Feature map remains in_progress. HostedCIunverified; publication[skip ci].

TR4 standalone linking runtime preparation: follow traffic-linking-runtime-design en/ja. Reuse the fixed29 real loopback fixture/two-boot candidate without changing the default app profile. Exercise TrafficStore25+4 selection and20-row candidate search, TrafficBindingStore single bind/dispatch scope/nonce/clear; existing finding picker repeats idempotently and must preserve the independent browser receipt. Add unit contract tests before code, review and real VM evidence. No claim of TrafficScreenModel/Root/native input execution, multi-host delete proof or full TR3/TR4/TR5 completion.

TR4 standalone Core linking runtime extension verified:2c495b4 compileRED→da7f3ae five-case GREEN→dfb2d7a real-probe integration. Fresh CPU1 candidate disk completed actual2boots/2cooperativeStops/2cleanAudits,25+4 traffic selection, paged candidate9101, bind2/version1, nonce rejection/matching clear, identical idempotent picker receipt/version and persisted final1binding/2snapshots. Full native exercise projection matches the independent frozen-browser API receipt exactly.972Swift(971pass/oneexistingAXskip),179Python; new exercise104/105LLVM attributed entries. Release build/DEBUG-symbol exclusion/full-argument guardexit2 passed. Previous signed app/default guest preserved; no promotion or actual screen/root/input execution. See traffic-linking-runtime-design/verification and bugs/traffic-linking-runtime en/ja plus evidence/traffic/linking-runtime-verification.json. Multi-host delete/filter/sort/capture settings, blob, actual native/browser/AX/multiwindow and original kernel/provider/harness/release gates remain open. HostedCIunverified; publication[skip ci].

TR3 blob-original extension preparation: follow traffic-blob-design en/ja. Use structured exchange-side metadata in a separately versioned managed backend overlay; do not parse untrusted raw @blob markers or create fake finding/binding mutations. First container-only Go TDD for exact stored blob association/size/hash and spoof/invalid/missing/corrupt cases. Then handler/auth, pinned build provenance, native manifest/verified staging/auth/VM/save UI and actual bytes. Fixed browser/default guest remain unchanged; no nonworking controls or completed blob gate claims.

TR3 blob metadata primitive software checkpoint: managed overlay over exact e75ae371 implements stored id/side/blob/length association without raw marker parsing. c937d64 compileRED→a4e95b9 ordinaryGREEN; review led9856893 FIFO5.01s/symlink runtimeRED→c40ec74 descriptor-anchored no-follow/nonblocking regular-fileGREEN; bbe7072 adds literal/NFD/legacy/corrupt cases. Seven new top-level cases/18 new pass events; full traffic package61 pass events, no skips/failures, in pinned Linux/arm64 container with offline tests and verified modules. Overlay54/59 statements(91.53%); whole package66.3% separately disclosed. Frozen checkout/default guest/native app unchanged, baseline21/27/243 and prior app strict signature verify. No route/auth/stream/native manifest/export/UI/deployment yet; future managed streaming must use hardened opener too. See traffic-blob-design, traffic-blob-metadata-verification, bugs/traffic-blob-metadata en/ja and evidence/traffic/blob-metadata-verification.json. All full blob/VM/browser/native/kernel/provider/harness/release goals remain open; hostedCIunverified, publication[skip ci].

TR3 blob HTTP wiring plan: container TDD against real Handler/JWT middleware for structured metadata, strict query/byte scope, generic400/404/503 distinctions and exact original binary/length. Apply a reproducible patch only to the managed source to register the route and redirect existing Traffic.Blob through the hardened opener. Keep source/image/native staging/UI/export/promotion gates open until individually tested; no auth exemptions or external targets.

TR3 managed blob HTTP/build checkpoint:6d7f613 realHandler route/symlinkRED→2d50dff HTTPGREEN; independent review found lost legacyhash normalization,859d09d RED→df9df85 GREEN;f6456f8 bounds/full build. Authenticated structured metadata and hardened existing stream are implemented in a patch applied only to managed source. Overlay15cases/26pass events; offline traffic+server373pass events(270top-level),102existingDB/fixture skip events, no failures. Handler30/30 and primitive60/65Go statements; full package coverage/skips separately disclosed. PinnedLinux/arm64 CGO0 stripped backend built reproducibly with SHA2560cbb7cb32f05843de7b733fb76ed4e22b9b2acd386878d4ce34b89d819a3750a, saved only in ignored managed-backend-blob-v1 with inputmanifest. See traffic-blob-http-verification and bugs/traffic-blob-http en/ja plus receipt. Frozen checkout/default guest/staged app unchanged; no native source or save UI yet. Next: managed guest provenance/real endpoints, native typed manifest/verified staging/auth/VM/UI ownership/cancellation/save and actual bytes. Full21 workflow/kernel/provider/harness/release gates stay open; hostedCIunverified, publication[skip ci].

TR3 native blob staging plan: follow traffic-blob-native-design en/ja. TDD finite literal id/side/hash/Int64 metadata and fixed download route, share only internal size/hash staging contract, keep two public typed transports and original finding semantics, preserve auth/VM/cancellation/receipt/cleanup. No attachment/JSON cap on originals and no forged finding. Require existing evidence suites plus new blob file/auth tests; guest provenance/live bytes/panel/UI still pending and default profile unchanged.

TR3 blob runtime plan: follow traffic-blob-runtime-design en/ja. Build a disposable CPU1 candidate from verified immutable parent, old kernel/initramfs/capture init and managed binary; test wrong-hash rejection before ext4. Add DEBUG captured-blob mode retaining old mode/reference projection, structured ordinal4 metadata/full binary save, inline/bad-length refusal, real stop-before-publication, reboot/persistence/source/no-agent audits. Preserve default profile; actual mid-transfer witness/UI/panel/root/keyboard/VoiceOver and all original gates stay open.

TR3 native blob/runtime checkpoint: a42c40a completes nine native blob cases and seven proof cases after preflight/auth causality REDs. Actual signed DEBUG managed candidate run passed two boots/stops/audits, full262401-byte original/reboot equality, inline/bad-length rejection and stopped-VM publication rejection with original auth revision retained; fixed browser projection unchanged. Swift988(987pass,one existing AXskip),Python179, localization/baseline checks. Staged app rebuilt/signed with unchanged default guest; experimental candidate not promoted. See traffic-blob-runtime-verification and bugs/traffic-blob-proof en/ja plus receipt. Actual mid-transfer witness, native source save UI/root/window/panel/input/AX and all21/kernel/provider/harness/release gates remain open. HostedCI unverified; publication[skip ci].

TR3 controlled mid-transfer cancellation plan: follow traffic-blob-interruption-design en/ja. Add DEBUG exact-manifest/operation TaskLocal pause after real staging append; require positive partial bytes and actual open socket cancellation plus cleanup/auth continuity. Preserve stop/reboot/reference and default profile. TDD witness/scope/invalid/replay/timeout contracts, focused/full suites, actual VM and release exclusion. This is controlled reader cancellation, not spontaneous network-failure acceptance. Save UI and all original gates remain open.

TR3 controlled interruption checkpoint:4a9f3ee actual signed snapshot passed7939/262401-byte partial staging, owned open-socket cancellation, unchanged authentication, absent destination/stage, continued VM operation, normal original-byte equality, cooperative stop refusal and reboot/reference/audits. Retained runtime2026-10-30 revalidated2026-11-04. Swift998(997pass,one existing AXskip),Python179, witness48/48 and CLI55/62 combined line coverage; wider controller363/504 separately disclosed. See traffic-blob-interruption-verification and bugs/traffic-blob-interruption en/ja plus receipt. Controlled reader pause does not prove spontaneous network failures. Native save UI/root/window/panel/input/AX, all21/browser/kernel/provider/harness/release gates stay open. HostedCI unverified; publication[skip ci].

TR3 save UI design: follow traffic-body-save-ui-design en/ja. Fixed browser independent packet viewer versus finding-bound downloads explicitly distinguished. Lazyweb209165c3 evidence supports status/cancel only; no screenshot visual acceptance. Next implement capability contract, retained detail-scoped export model TDD, root/panel/UI integration and actual managed model export, preserving all21/keyboard/AX/kernel/provider/harness/release gates.

TR3 save capability contract:7070fcd compile RED to91127ab focused6 GREEN (two new profile cases, four existing boundary cases). GuestArtifacts now decodes optional managedCapabilities and declares original export only for rootDisk/systemDisk plus both known flags. Missing/unknown-only/partial flags remain false; future extra strings retain compatibility. Malformed capability types reject decoding and declared flags never bypass file hashes. This is a compatibility declaration, not readiness/auth: VM epoch propagation, export model and UI remain next. No default guest promotion or app-feature acceptance is claimed.

TR3 runtime availability:ec58601 adds current verified boot declaration lifecycle and computed running/ready/machine gate. State matrix, failed-start and signed actual two-boot/two-stop gate assertions pass with existing source/cancellation/persistence/reference proof. Swift1002(1001pass,one existingAXskip), gate7/7 lines. See blob-runtime-capability-verification receipt and save UI design en/ja. Next: retained export model and root/window/panel ownership; UI/full21/kernel/provider/harness/release gates stay open.

TR3 export model:e778df7 eight focused GREEN after wrong-receipt and admission reentrancy REDs. Immutable literal detail scope, availability/owner checks, cancel/drain, verified receipt commit/discard, cleanup feedback. Swift1010(1009pass,one existingAXskip),Python179, model/scope158/163 lines. See model RCA en/ja + body-export-model-verification receipt. Next root/detail retention, actual model-VM export and save panel/UI integration; no model unit check substitutes browser21/input/AX/kernel/provider/harness/release gates.

TR3 parent bridge:4e57eba retains body export per exact detail lease/owner/revision/raw ID/fresh detail and retires on close/reset. Held transfer and observation-reentrant stop regressions pass; late cleanup failures retained for root collector. Related29/fullSwift1013(1012pass,oneAXskip)/Python179, parent522/547 lines. No root injection, visible save action or actual model-VM/UI acceptance yet. Next root retirement collector and detail/panel wiring, preserving all original gates.

TR3 root/save controls checkpoint:4643050 connects typed authenticated metadata/export, captured VM+auth generations, exact preview save controls, anchored panel and App-shared retirement notices, including successful-file cleanup warning retention. Related59/fullSwift1018(1017pass,oneAXskip)/Python179. Actual Core VM2boots/stops/audits and distinct generation/ref/byte/cancel/persistence proof pass; not the frontend model or GUI. See traffic-body-save-ui-verification en/ja + receipt, Root0/420 coverage disclosed. Default guest controls remain hidden/no promotion. Next exact model-to-VM proof and unlocked native/browser UI/panel/input/AX acceptance; all21/kernel/provider/harness/release remain open.

TR3 production-model VM checkpoint:f56e388 uses the shared package Core model/protocol/collector (migrated8b19034), not a duplicated harness. Actual signed two-boot run saves/rereads262401 bytes twice, retires actual held verified receipts without publication/staging/notices, audits zero-agent/source counts after both model exercises and preserves fixed reference/persistence/stops. Swift1020(1019pass,oneAXskip),Python179; model193/193,collector29/29,helper100/115 combined lines. See traffic-body-model-vm-verification en/ja and production-model-vm receipt. Automated chooser is not real panel/UI acceptance; default guest/kernel/provider/harness/release/all21 gates remain open.

CP1a endpoint identity foundation: d41623a completes compile RED be01b38 / initial GREEN fce0f79 plus review-discovered escaped-authority runtime RED1740aad / corrected GREEN. Existing profile/draft metadata only; no schema, format, key, endpoint, UI or guest changes. Swift1023 (1022pass,one existing AXskip), identity27/28lines. See cloud-endpoint-identity-verification en/ja. CP1 remains open for explicit selection/persistence/capabilities/guest request fixtures; CP2–CP4 and all original VM/browser21/release/harness gates remain open. HostedCI unverified; publication[skip ci].

CP1b checkpoint:70a991f adds fresh four-provider preset drafts after compile RED844299b; existing format/baseURL save encoding and typed reload are fixture-verified without inheriting ID/key/model/proxy/overrides. Actual pinned backend HTTP model-list and Stream code passes four Gemini/Groq loopback subtests plus two parents under Docker RUN --network=none; no production Go changes. Swift1025(1024pass,one existing AXskip),Python179,preset13/13lines,app rebuilt/strict-signed without launch,frozen browser clean. See cloud-presets-verification en/ja and receipt. No actual DB/cloud/TLS/signatures/UI acceptance claimed; CP1 capability/request isolation and CP2–CP4 plus original21/VM/kernel/harness/release gates remain open. HostedCIunverified; publication[skip ci].

CP2 tool-history checkpoint:aa2a6bf runtime RED signature loss/interleaved arguments ->3fe4c64 GREEN, review scope REDa7383ee ->cb77140 GREEN. Typed persisted signature+endpoint/model context, indexed streams/early metadata, copied scope filtering and recursive Anthropic isolation in checked managed norma0.4.3 patch; original cache24files and patched26files exact-verified. Full Linux tests527pass/116existing skip events(parent/subtests),Python179; new helper6functions100%,wholellm74.2% disclosed. Managed cloud1 CGO0 ELF/arm64 backend29294754B SHA94ce92158f608d1b56b2e19a5e8f73e9eb596019f6fc0df96da1bd2891bedb56 compiled/exported only. See cloud-tool-history-verification and bugs/cloud-tool-history en/ja plus receipt. No VM/default promotion, actual DB/cloud/tool/UI acceptance; CP2/full4provider and original21/kernel/harness/release gates remain open. HostedCIunverified; publication[skip ci].

CP1b actual profile VM checkpoint:55e7771 signed DEBUG probe on independently bound CPU1 cloud1 candidate passed two Apple Virtualization boots/stops/audits in18.587s with distinct generations, correct live backend version,401 auth gates,4 actual preset rows and renamed Gemini retained on same PostgreSQL disk after restart. Masked suffixes and raw-key redaction checked with synthetic keys. Both boots zero conversations/LLM records, NIC0/shares0. Swift1027(1026pass,one existing AXskip),Python179,diagnostic216/233lines and115/141regions,release and negative CLI guards pass. See cloud-profile-vm-verification en/ja and receipt. Actual tool transcript/restart replay, cloud egress, native/browser21, default/kernel/harness/release gates remain open. HostedCIunverified and publication[skip ci].

CP2 actual ChatAgent process checkpoint. 0920bce reproduced signature-before-input launching an invalid Read. 1db2758/1c2d095 bind indexed dispatch to completed history blocks. c4209b5/c48ac4e validate raw batches and callback cancellation. 3e8aae8/4b4c242 bind early fragments and reject unmatched inputs, then retain the original tool context across scheduler and semaphore. Both isolated Linux process modes replay original signed call/results after witness deletion, with zero resumed tool runs. Full Go589pass/116existing skip events and Python179 pass. Combined SDK streamAndExecute88.5%, raw validation88.9%, queue/scheduler100%, broader78.3%. Compiled cloud2 ELF arm64 CGO0, SHA0455fb4255796a6c1ba1dc5545cbdbb39f722492ca6e48775f8ce8ff7b16e6bf. See cloud-indexed-execution-verification and bugs/cloud-indexed-execution en/ja. Dedicated VM reboot with normal chat API, live cloud, native/browser21, kernel/default promotion, harness and release remain open. Hosted CI unverified with publication [skip ci].

CP2 actual VM history checkpoint. Signed DEBUG 9b5a3c3 runs cloud2 through production Swift auth/LLM/chat API with two cooperative CPU1 VM boots on one state disk. Fixed loopback fixture accepts 2+1 requests and verifies the original signed call/arguments/result digest after reboot with the volatile file absent. PostgreSQL activities retain one Read/result pair and add a new final reply. Swift1028 with1027 pass and one existing AX skip, Python183, combined diagnostic226/243 lines. Release and negative CLI guards pass. See cloud-history-vm-verification en/ja and receipt. Cloud egress, actual native/browser workflows, default guest/kernel promotion and release remain open. Publication [skip ci].

CP3 provider redirect checkpoint. Two loopback servers reproduce one cross-port bearer request each from discovery and completion. Review adds RED coverage for redirect body leaks in captures and errors and for malformed Location. The managed cloud3 patch refuses cross-origin hops, drops redirect bodies and preserves same-origin 307 requests. Five focused Go tests pass, with 594 pass and 116 existing skip events overall. Python guest artifact tests pass 183 cases. Verified Linux/arm64 binary and input digests are in cloud-redirect-verification en/ja and the receipt. Stored-key binding, VM egress, live provider verification, native/browser comparison and default guest promotion remain open. Publication uses [skip ci].

CP3 stored credential checkpoint. Cloud3 reproduces six altered-profile requests, two global fallback requests and a moved key on blank save. Review reproduces two sibling-path requests. Cloud4 binds saved keys to format, URL and proxy before requests and locks the profile row across a blank-key update. The PostgreSQL fixture observes the concurrent lock and retains the newly committed key and target. Final PostgreSQL 14 pass events, offline Go 594 pass and 117 skips including the PostgreSQL fixture, and Python 183 pass. See cloud-credential-target-verification en/ja and the receipt. VM egress, live cloud, native/browser comparison and default promotion remain open. Publication uses [skip ci].

CP3-A egress policy checkpoint. Core constructs nine finite provider requests, rejects mixed special-purpose DNS answers, and checks the exact TLS certificate name. Five focused tests, full Swift 1032 pass with one existing AX skip, release build and Python 183 pass. Host connect-only system libcurl diagnostic verifies 13 numeric TLS peers across all four providers, with zero HTTP requests. A direct failure sent zero requests to the configured proxy with proxying explicitly disabled, versus one with the default. See cloud-egress-verification en/ja and the receipt. Next is the production direct transport, guest vsock bridge and signed VM isolation proof. Default guest, live API and browser comparison remain open. Publication uses [skip ci].

CP3-B1 direct TLS worker checkpoint. Host libcurl pins the numeric address before opening the socket and verifies the actual peer before sending bytes. Loopback TLS checks exact POST body and response, wrong/untrusted certificate, handshake/response cancellation, timeout, response cap and proxy denial. Swift 1034 pass with one existing AX skip, Python 189 pass including six loopback tests, clean Clang analyzer and ARM64 release build. Missing-intermediate loopback probe records zero issuer/provider bytes. Explicit certificate-fetch control is required before VM listener activation. HTTP response framing, vsock integration, signed VM isolation, live APIs and browser workflow comparison remain open. See cloud-egress-transport-verification en/ja and the receipt. Publication uses [skip ci].

CP3-B2 offline trust checkpoint. A pinned POSIX socket and SecureTransport authentication break enforce hostname, chain and network-disabled certificate evaluation before sending HTTP. The missing-intermediate fixture rejects, the complete chain succeeds and the issuer/OCSP/CRL sentinel sees zero connections. Ten loopback cases, 1034 Swift passes with one existing AX skip, 193 Python passes and ARM64 release build. Host retry verifies 13 TLS 1.2 peers across four providers with zero HTTP requests or credentials. The deprecated TLS 1.2 backend stays confined to its transport target. Next: bounded HTTP response framing, dedicated vsock lifecycle and signed VM isolation. Live API and browser comparison remain open. Publication uses [skip ci].

CP3-B3 response framing checkpoint. The TLS worker emits bounded status/body/end events for fixed, chunked and close-delimited HTTP. Exact framing and clean TLS are required for end. Review-driven ASCII coding and chunk extension grammar checks reject malformed metadata. Six focused tests cover all split points and incomplete prefixes, cumulative limits and failure propagation. Swift 1040 pass with one existing AX skip, Python 193 pass and ARM64 release build. See cloud-egress-response-verification en/ja and receipt. Next is the dedicated vsock protocol and VM lifecycle, then signed VM isolation, live APIs and browser comparison. Publication uses [skip ci].

CP3-B4 host vsock checkpoint. Port 8790 is a ready-VM opt-in with finite single requests, bounded response frames, peer disconnect cancellation and four process slots held through descriptor closure. Stop guards prevent listener reactivation during suspension and replacement boot until both stop calls return. Seven focused real UNIX socket tests, 12 repeated runs, Swift 1047 pass with one existing AX skip, Python 193 pass and ARM64 release build. Signed DEBUG cloud-history regression passes two actual isolated boots and cooperative stops with the listener disabled. See cloud-egress-vsock-verification en/ja and receipt. Linux client, actual virtio streaming and cancellation, activation, live APIs and browser comparison remain open. Publication uses [skip ci].

CP3-B5 Linux client checkpoint. Cloud5 includes opt-in AF_VSOCK CID2 port8790 routing with fixed operations, body limits, context cancellation and no direct fallback. SDK and task layers require the broker terminal, including OpenAI DONE, Anthropic and Responses error events, non-200 and captured quota responses. Unconfirmed POSTs do not replay. Offline Go 613 pass/117 skip events, 19 focused events included, PostgreSQL 14 pass, Python 193 pass and verified CGO-disabled Linux ARM64 ELF. See cloud-egress-guest-verification en/ja and receipt. Signed VM delivery, guest init activation, real providers and browser parity remain open. Publication uses [skip ci].

CP3-B6 signed VM checkpoint. A cloud5 candidate with the opt-in guest init
passed authenticated model discovery and streaming chat for OpenAI, Gemini
and Groq through actual Linux AF_VSOCK and the host listener. The DEBUG
fixture stopped an in-flight stream on cooperative shutdown. Fresh disk,
401 authentication gate, NIC0, shares0 and credential log checks passed.
See cloud-egress-vm-verification in English and Japanese and the receipt.
Anthropic VM delivery, live provider requests, normal app activation and
native/browser comparison remain open. Publication uses [skip ci].

CP3-B6 four-provider follow-up. The signed cloud5 probe now checks all four
model routes and all four streaming routes, including Anthropic's API key
and version headers and its native Messages events. The same isolated
guest passed the held-stream cancellation and stopped-log audits. Live API
acceptance, normal app activation and native/browser comparison remain open.
Publication uses [skip ci].

CP3-C preview startup checkpoint. The regular DesktopRuntime enables the
production listener only for an explicit launch opt-in and the exact
verified manifest. The app preview uses a separate state and Keychain
account. Signed VM probes pass enabled and disabled boots, tamper refusal,
cooperative stop and the four-provider synthetic regression. The ARM64
Release preview was bundled and strictly signature-verified. GUI, real
provider calls and frozen-browser parity remain open. Publication uses
[skip ci].

CP4 new-profile menu checkpoint. The Mac LLM settings offer four provider
presets and a manual configuration. Existing editor actions and saved
profile editing use the same contracts. Five fresh drafts render offscreen
in both languages. See the bilingual provider-menu design and verification
for the comparison against the frozen browser. Live interaction, keyboard,
VoiceOver, real APIs and full browser parity remain open. Publication uses
[skip ci].

CP3-D live model endpoint checkpoint. The signed VM reached all four fixed
provider routes with deliberately invalid values and received 401 for
OpenAI, Anthropic and Groq and 400 for Gemini. Finishing explicitly framed
responses before TLS closure resolved the observed Gemini read abort.
A final repeat yielded no confirmed upstream statuses. Connection
stability, valid-key calls, native controls and browser acceptance remain
open. See the bilingual live-models verification. Publication uses [skip ci].

CP3-D connection timeout follow-up. Signed diagnostics reproduced timeouts
before TLS and HTTP at the Mac TCP stage. The broker can now try another
vetted address after a pre-dispatch deadline, with a four-second per-address
budget. Loopback reproduces the former timeout classification and verifies
both sides of the dispatch boundary. The signed synthetic VM regression
passed. Two production-route repeats yielded no confirmed status, so live
stability remains open. See bugs/cloud-egress-connect-timeout in English and
Japanese. Publication uses [skip ci].

CP3-D paired TCP follow-up. Same-address controls reproduce a pending
connection before VM creation, including with select. A PID-matched
macOS filter record confirms an initial verdict was pending on one
timed-out signed probe socket. Little Snitch is the active extension.
No TLS or HTTP was dispatched by these probes. Release app policy
and authenticated live stability remain open. See the bilingual
connection-timeout investigation and paired TCP receipt.

CP4 signed native LLM navigation follow-up. The actual first visit
exposed a missing workspace observation. The regression and real
signed retest verify first-click display. The editor and rotation
sheets now inherit the chosen language explicitly. All five Japanese
choices, keyboard selection and dismissal, English Groq and Rotation,
and switching back to Japanese Custom were observed. Current browser
authentication, VoiceOver and live API acceptance remain open.

### P4 Agents catalog

The signed-in Agents screen must list every guest agent in the same order as the frozen browser, including disabled agents, with matching names, descriptions, type labels and binding counts. Localize seeded labels in English and Japanese and preserve custom labels verbatim.

Use the authenticated guest `GET /api/agents` and an adaptive card grid. The pinned browser supplies the field and localization contract. Lazyweb's Superhuman Agents desktop result supplied a secondary reference for grouping names, descriptions and metadata inside cards. Display load failure separately from an empty catalog and keep mutations and prompt editing outside this checkpoint.

Test the wire shape, order, optional fields, invalid responses, cancellation and language behavior first. Then build the native screen and compare it against the frozen browser source. Record actual paired GUI and editor acceptance separately.

### P4 Agent prompt details

A signed-in user must be able to open an agent card and inspect the current prompt, its variables and version history, plus the normal and supported task-timeout wrap-up prompts and round budgets. Display stored prompt bytes as text, including user-authored language and spacing.

Use an authenticated detail GET, require the response to name the requested agent, and cancel obsolete loads on dismissal. The frozen editor drawer supplies the tab order and content. Lazyweb's audit-history references support separating the version list from the selected version text. Use a native sheet with Prompt and Wrap-up tabs, and a disclosure row for each saved version. Write, restore, diff, configuration and binding controls remain separate tasks.

Verify route validation, response identity, preservation of literals, version ordering and defaults, server status, cancellation, native navigation and the disposable pinned backend.

### P4 Save agent prompt versions

The prompt editor must send the exact draft to the pinned guest, leave prior versions available, and display the acknowledged version. An invalid template must leave the draft editable. After an interrupted or unconfirmed write, preserve the draft and require a history read before another save. A historical version can be copied into the draft for a subsequent explicit save.

Use the existing authenticated agent detail transport. PUT the literal template and the same empty note as the pinned editor. Serialize the save with its history refresh. Keep the current draft visible while it saves, provide an explicit history refresh for uncertain outcomes, and confirm before closing a dirty sheet. The frozen editor supplies the editing and history actions. Lazyweb's Notion and Canva results show the value of keeping history reachable alongside the editor.

Verify request bytes, valid and invalid templates, lost acknowledgement and stale history, duplicate dispatch prevention, and saved-version replay into the draft. Compare the isolated native guest with the fixed browser backend before considering the save workflow accepted.

### P4 Prompt preview and version comparison

Render the current draft with the guest's sample variables and show the result without changing the saved prompt or history. Preserve the pinned API's empty-draft fallback to the current saved prompt. Compare a selected past version with the current saved version, keeping additions, removals, and unchanged lines in the frozen browser's order.

Use the existing authenticated transport for preview and a local line comparison with a bounded matrix. When a comparison exceeds the bound, offer both originals without computing a diff. Keep preview output and diff lines selectable as literal text. Lazyweb's v0 reference informed separation of editing from inspection. The frozen browser controls the behavior and labels.

Verify the request, parser diagnostics, unchanged version history, exact whitespace and line-ending behavior, repeated-line ordering, and large comparisons before trying the native sheet and pinned backend.

### P4 Restore a built-in agent prompt

Match the pinned guest reset endpoint. Restore the guest's current built-in template as a new saved version and keep the previous prompt in history. Offer the action on built-in agents and confirm before replacing the editor draft. If acknowledgement or history verification is interrupted, use the existing mutation recovery flow and keep unsaved input available.

Use the frozen browser editor's action label. The Productboard restoration dialog returned by Lazyweb informed showing a cancel action and the consequence before committing the restore. Verify the request, history, custom-agent rejection, and stale or uncertain responses. Compare the disposable native and pinned browser fixtures without running an agent.

### P4 Edit agent wrap-up settings

Match the pinned normal and supported task-timeout wrap-up save and reset endpoints. Preserve literal prompt overrides and interpret empty text and zero rounds using the guest defaults. Keep drafts for both sections independently and verify the persisted pair of fields before displaying success.

Use the authenticated editor and the existing mutation gate. Keep the saved default available as a disclosure and confirm reset. The pinned browser defines the two sections. Lazyweb settings references informed keeping the field labels and actions in each section. Test exact writes, validation, partial failure, and isolation between drafts before comparing native and pinned fixtures.

### P4 Agent model and execution limits

Read the model profile choices and agent limits from the authenticated detail endpoint. Allow an explicit model binding or inheritance, with limit controls on the same agents as the frozen browser. Send only changed, visible fields. Confirm the affected fields by reading them back, preserving drafts in other sections and after a partial write.

Group the model selection and numeric limits with the prompt settings. The frozen editor defines their visibility and the Cursor settings result from Lazyweb informed the model picker layout. Verify numeric bounds, omitted versus null fields, unsupported limits, missing profiles, and readback before comparing with the pinned reference.

### P4 Agent Web search and interactive shell preferences

Show the frozen editor's per-agent preferences where supported. Read the guest-wide Web search switch and keep the per-agent control unavailable until that switch is confirmed on. Check it again before saving a changed Web search preference. Keep shell and other settings independently editable, with no guest-wide writes from this form.

Use the existing changed-field patch and authenticated readback. Preserve existing flags when hidden, unavailable, or untouched. Place the status explanation by the control, informed by the Square and Workflowy settings results from Lazyweb. Test the gate, request shape, and a gate change during editing. Compare with the pinned fixture without launching tools or agents.

### P4 Agent MCP and skill visibility

Display the guest MCP servers and skills in the agent editor. Read the selected agent's current assignments. Save each checkbox through the frozen guest's resource-specific endpoint, so changing one assignment preserves concurrent changes to other assignments. Read back the saved membership and refresh the card counts.

Use the current detail's numeric agent identity and the resource catalog's IDs. Keep failed or uncertain requests separate from an empty catalog and require a fresh read before retrying an unverified change. The frozen editor and Lazyweb permissions references inform the two checkbox lists. Test the payloads, readback, and failed writes, then compare with disposable native and browser fixtures.

### P4 Keep seeded skill removals across guest restarts

Seed default skill memberships once per database. Commit the marker and initial memberships in one transaction. For databases already initialized by the pinned backend, recognize its completed intercept seed marker and adopt the existing memberships during migration. Validate fresh setup, same-database restart after removal, and migration from the fixed browser backend.

Tool-run history implementation order: verify the authenticated wire
contract and filter ownership, then compare a populated disposable guest
and pinned browser fixture. Cover multiple pages, non-shell and failed
runs, missing results, non-ASCII input and empty/error states. Verify
that changing the page does not change the aggregate. Then validate
native list, detail and summary with actual keyboard and visible
browser comparisons. The authenticated native screen is implemented.
Native in-flight cancellation on screen departure is recorded below.

The pinned backend API oracle passed on a fresh offline reference
container with 54 synthetic runs. It checked 30 list responses and
six filtered aggregates, initial empty state, protected routes,
rejection of a second seed, and cooperative shutdown. Rerun with
`python3 script/tool_run_reference_host.py` using the pinned local
reference runtime image. The [reference receipt](../evidence/tool-runs/pinned-browser-api.json)
is the browser backend side of the comparison. The signed DEBUG
`VMProbe --tool-runs ARTIFACTS NEW_PRIVATE_OUTPUT` then seeded the same
data in a fresh isolated VM and read through the native ToolRunService.
The probe and comparison both pin the reviewed VM manifest digest.
The [comparison receipt](../evidence/tool-runs/native-api-comparison.json)
shows exact matches for all six decoded snapshots, including all 30
pages and six aggregates. The run also checked initial empty state,
two unauthenticated rejections and cooperative shutdown. Recheck a
native output with `python3 script/compare_tool_runs.py OUTPUT/tool-runs-vm.json`.
One repeat stopped at seed with guest ext4 inode checksum errors.
A fresh run of the same signed probe and pinned artifacts reproduced
the successful receipt. VM boot and storage stability remain open,
independently of the UI checks below.

The pinned browser also passed a rendered Chromium run on the same
54 records. It verified the six column labels, literal detail output,
50 and 4 rows on the two default pages, all three per-tool counts
with the summary opened from page 2, five combined-filter rows and
the empty result. Browser input verified Tab between filters and
Escape to close both detail and summary. The Chromium and backend
containers shared an isolated loopback namespace and were removed.
Rerun with `python3 script/tool_run_reference_host.py --browser`.
The [browser receipt](../evidence/tool-runs/pinned-browser-ui.json)
is paired with an [external native UI receipt](../evidence/tool-runs/native-ui-comparison.json).
A signed DEBUG app using the reviewed VM displayed 54 total records
and four rows on page 2. Its detail preserved the literal output.
The page-2 summary displayed 54 calls and 12 failures, with 18 calls
and four failures per tool. Tab moved between filters, Return applied
the combined filter (five records), and Escape closed both sheets.
The empty filter displayed zero records. The review removed its
temporary Keychain item and stopped the VM cooperatively.
Use `--native-diagnostics NEW_PRIVATE_DIRECTORY --native-review --no-llm-review --tool-runs-review`
with a DEBUG bundle carrying the reviewed guest. Write the fixed
`native-review-finish` marker to end the disposable review.
The rendered list-error comparison is complete. The [pinned browser](../evidence/tool-runs/pinned-browser-error-ui.json)
displayed its empty state for a targeted HTTP 500 injected by Chromium
and recovered to six matching records. The [Mac app](../evidence/tool-runs/native-error-ui.json)
displayed a localized HTTP 500 error from the isolated backend and
recovered to 54 records using Refresh. The fault fixture can be run by
adding `--tool-runs-failure-review` to the DEBUG review invocation.
Wait for `tool-run-failure-ready`, inspect the list, then write
`tool-run-failure-restore` in the private review directory. The
`native-review-ready.json` marker confirms restoration before Refresh.
The visual review compared the English screens at a 1180 × 800
logical viewport/window. Both show six columns in the same order.
The browser places pagination above the table and opens details in
a trailing drawer. The Mac places pagination below the table and
uses a sheet with stacked input and output. The browser uses bars
and percentages in its summary. The Mac uses native
table headers and numeric columns. The review identified two missing
values in the Mac UI, the visible row range and each tool's share of
total calls. Both values are now shown alongside the existing
pagination and summary counts. The comparison uses the browser's
light appearance and the Mac's dark appearance. The disposable
Chromium image lacks Japanese glyphs in the screenshots.

The revised Mac build was checked in Japanese with external native
automation. It showed `1–50 / 54` and `51–54 / 54`, and the summary
opened from page 2 showed `33.3%` for each tool. See the
[visual comparison receipt](../evidence/tool-runs/visual-comparison.json).

The [filter control receipt](../evidence/tool-runs/filter-controls-comparison.json)
records the difference for `8802x`. The browser strips the letter and
automatically shows 26 records. The Mac keeps the draft, explains
the numeric requirement and retains the 54-record list after Return.
Correcting the draft and pressing Return shows the same 26 records.
In Chromium, an older request was held, the newer filter rendered
its empty result, and the older real response then completed with
six records. The empty result remained visible at the post-response
observation.

Finite JSON calls now shut down their owned vsock descriptor when
the caller cancels. VM stop also interrupts these sockets without
adding them to the file-transfer interruption count. The socketpair
regression waits for the peer to receive a request, cancels while
the peer is silent, and checks peer EOF. The signed Tool Runs probe
also cancels a real list call after PostgreSQL reports a lock waiter.
The caller receives cancellation while the fixture lock is still
held. After release, the probe reads 54 records and repeats the six
reference comparisons. The [native screen trial](../evidence/tool-runs/native-screen-departure.json)
then refreshed the list and selected Account. The list exchange ended
while the guest lock was still held. Returning after lock release
showed 54 records again. This observation measures the Mac-side
exchange. PostgreSQL query completion after disconnect was outside
the trial.

For this trial, add `--tool-runs-cancellation-review` to the native
review arguments. The signed DEBUG bundle can carry the pinned fixture
under `Contents/Resources/ToolRunFixture` with the original relative
paths for the four hashed Python sources and
`evidence/tool-runs/pinned-browser-api.json`. Start the lock using
`tool-run-cancellation-start` after the ready marker and the initial
list. Wait for `tool-run-lock-held`, then refresh and select Account.

LLM call history proceeds from the three read contracts to selection and pagination state, then native screen and mutation work. Use synthetic records to compare filters, legacy rows without raw bodies, raw text, failures and cancellation on the browser and native VM before closing the feature gate.

The read-only native screen now exposes the pinned list columns, task picker, pagination, and lazy row detail. It uses an explicit Apply Filters action and opens request and response in a native sheet. The raw switch is disabled when both raw bodies are absent. The pinned browser source supplied the workflow. The Lazyweb search surfaced an adjacent observability dashboard. Native table and sheet behavior followed the existing Tool Runs pattern. The feature remains in progress through recording, deletion, and paired fixture acceptance.

Recording and confirmed task deletion are now connected to the native history screen. The pinned browser defined the operations. Lazyweb activity references supported a separate recording switch and a confirmation that identifies the deletion target. Local tests cover the scoped PUT, independent readback, exact deletion path and invalidation after failure. Equivalent synthetic data still needs browser and native VM acceptance.

Pinned browser mutation checkpoint. In isolated Chromium, four synthetic rows confirmed recording readback off/on/off, task filtering, Escape preserving all rows, and confirmed deletion of only `task+A`, with both the other task and an unassigned row retained. Both temporary containers were removed. Reuse these inputs for the signed native VM comparison. Native controls, readback and isolation remain separate acceptance checks. [Browser receipt](../evidence/llm/record-mutations-browser.json)

Signed VM mutation checkpoint. An ad hoc signed DEBUG probe used the production Swift service and store with the same four synthetic rows as the pinned browser. The off/on/off readback, two filtered rows and remaining IDs after scoped deletion matched. Both unauthenticated endpoints returned 401. The VM stopped cooperatively with zero network hardware devices, external routes and shared mounts, and the temporary state disk was removed. The browser fixture hashes were corrected after rerunning the scenario and hashing the actual inputs. Native SwiftUI interaction, including confirmation and cancellation, remains pending. [VM receipt](../evidence/llm/record-mutations-vm.json)

Native history mutation comparison. A signed DEBUG fixture app used the production SwiftUI view and the same four rows as the browser. The recording switch read back off/on/off. Apply Filters showed two records for the selected task. Escape left all four rows intact. Confirmation named the task, defaulted to Cancel, and reported two records deleted. The backend independently confirmed that the other task and unassigned row remained. The trial exposed a traffic-specific confirmation label, which was corrected and rechecked in English. The VM stopped, and the temporary disk and Keychain session were removed. Read details, raw and legacy rows, error recovery, and cancellation of pending reads still require paired acceptance. [Native UI receipt](../evidence/llm/record-mutations-native-ui.json)

History detail comparison. Both the pinned Chromium UI and the signed native fixture showed parsed and raw request and response bodies and disabled the raw control on legacy rows. The native sheet now keeps the raw preference when reopening rows and follows the screen language, verified in English and Japanese. A browser detail HTTP 500 showed empty bodies, and selecting the row again after restoring the endpoint recovered. Native error recovery and pending-read cancellation still require paired checks. [Detail comparison](../evidence/llm/record-details-comparison.json)

Detail recovery comparison. On the pinned browser, HTTP 500 showed empty bodies and reselection after recovery restored the detail. When an obsolete response completed after selecting a second record, the second record remained visible. The signed Mac fixture used a temporary guest table rename to produce the actual backend HTTP 404, displayed the Japanese error, and reopened successfully after restoration. In a fresh cancellation trial, closing the loading sheet retired the host exchange while the database lock was still held. Reopening after release showed the original bodies. Guest SQL cancellation was outside this check. [Recovery receipt](../evidence/llm/record-detail-recovery.json)

History list comparison. The pinned Chromium UI and signed Mac fixture used the same 54 synthetic rows and matched on pagination, all three page sizes, model and session filters, empty results, and Tab between the filter fields. Mac Enter applies the filters. On HTTP 500, the browser retained the previous empty state while Mac showed an explicit error and recovered all 54 rows after Refresh. The Mac switch and all rows survived a VM restart. Wider keyboard and visual checks remain open. [List receipt](../evidence/llm/record-list-comparison.json)

History visual and keyboard comparison. The pinned browser displays detail below the table. Mac uses a sheet with the same request and response panes. With table focus, Mac Down selected the next row, Return opened that record, and Escape closed the sheet and retained the selection. Down then moved the selection again. The browser Tab trial did not reach history rows, and Escape did not close the inline detail. The comparison exposed missing copy buttons and time and latency in Mac detail and a truncated English token heading. Keyboard-only entry to the native table still needs verification. [Comparison receipt](../evidence/llm/record-visual-keyboard.json)

Mac history now shows detail time and latency, copies the displayed request or response, and uses the browser’s shorter Tokens heading. The signed Mac fixture verified all four clipboard values, including the raw SSE line breaks, disabled copy on empty payloads, and showed the full heading at default window size. Starting at Model, four Tabs reached the table, Down selected a row, Return opened it, and Escape closed the sheet. Verify the heading at minimum window width and compare copy in the pinned browser. [Copy and keyboard receipt](../evidence/llm/record-copy-keyboard.json)

The pinned browser and Mac copied matching plain-text and SSE payloads, including trailing newlines. The revised columns expose Tokens and Status at 980 points. Latency and longer status values still truncate. JSON formatting and clipboard presentation remain open. [Comparison receipt](../evidence/llm/record-clipboard-minimum-width.json)

The signed Mac fixture and pinned browser produced matching clipboard content for the three formatted JSON panes and raw SSE. Mac changes JSON whitespace only and retains key order, repeated keys, numeric spelling and escapes. Oversized formatting falls back to the source. [JSON receipt](../evidence/llm/record-json-clipboard.json)

At 980 points with the sidebar visible, Mac renders Latency and Status in English and Japanese. The pinned browser showed OK and Error for the same records. Mac keeps exact milliseconds while the browser rounds durations of at least one second. In Japanese the task picker, Profile and Tokens still show ellipses. [Compact comparison](../evidence/llm/record-compact-timing-status.json)

The signed Mac fixture confirmed the Japanese task picker, Profile and Tokens labels at 980 points. The table reapplies column widths on language change, and the English timestamp fit again after switching back. The pinned Japanese browser retained some English headings. Mac uses Japanese translations. Release-build verification remains open. [Language comparison](../evidence/llm/record-compact-language-switch.json)

Assets read service. The pinned backend returned 25, 1 and 0 rows across three offsets while retaining a total of 26. An exact DSL filter matched one root domain and invalid syntax returned HTTP 400. Swift transport tests cover encoded DSL, optional row fields, large identifiers, response consistency and independent counts. Repeat with the signed native VM and compare the SwiftUI tabs before accepting the workflow. Company management and asset deletion remain open. [Pinned API receipt](../evidence/assets/read-reference.json)

The signed native VM returned the same asset pages, total, counts and DSL outcomes as the pinned reference. Both asset endpoints returned 401 before login. The pinned browser opens on Company. Root domain pagination, DSL page reset and the empty IP tab were observed with the same fixture. These observations guide the SwiftUI tabs. [VM and browser UI receipt](../evidence/assets/read-vm-and-browser-ui.json)

The signed Mac app matched the pinned browser for the initial Company tab, 25 + 1 root-domain rows, the DSL search reset to page one, and the empty IP tab. The app stopped the disposable VM and removed its session key. Company management, asset deletion, DSL suggestions, populated states in the other tabs, and Japanese screen acceptance remain open. [Native UI comparison](../evidence/assets/read-native-ui.json)

Asset deletion service phase. Compare the request and count receipt against the pinned handler. Exercise exact ID encoding, invalid input, partial and invalid receipts, and HTTP failure at the Swift transport boundary. Follow with disposable guest and browser mutation tests, then native UI confirmation, refresh and selection checks.

The isolated pinned browser backend returned 1 for single deletion, 2 for a three-ID request containing a previously deleted asset, 0 for an absent asset, and HTTP 400 for an empty list. Readback confirmed the other 23 assets and the updated total. [Reference deletion receipt](../evidence/assets/delete-reference.json)

The signed Mac probe matched the pinned browser backend deletion receipts and received HTTP 401 for unauthenticated deletion. A fresh login after a cooperative restart showed the same 23 remaining IDs. In the pinned browser UI, cancel preserved 26 rows, single deletion left 25, and bulk deletion left 23 and cleared selection. Use these observations for the SwiftUI deletion comparison. [VM and browser deletion receipt](../evidence/assets/delete-vm-and-browser-ui.json)

The native deletion phase adds per-row and bulk selection, a confirmation with the captured count, and refresh after the request. Test last-page correction in Swift and compare cancellation, single deletion and bulk deletion against the pinned browser using 26 synthetic root domains in the dedicated VM.

In the signed Mac app at 980 points, cancel preserved 26 rows, one deletion left 25, and two selected deletions left 23 and cleared selection. The Mac confirmation displayed the selected count, and the Japanese view displayed the two-record result. The Mac uses a system alert and an inline result. Keyboard and VoiceOver verification and failure-state comparison remain open. [Native deletion comparison](../evidence/assets/delete-native-ui.json)

The company transport supports creation, scope addition and replacement, and deletion with or without attributed assets. The isolated pinned backend returned 409 for a normalized duplicate without changing scope. A mixed addition stored the valid rule, while an invalid replacement returned 400 and preserved both prior rules. An empty replacement cleared attribution. Deleting the company retained or deleted its asset according to the requested flag. Repeat the scenario through the signed Mac VM before comparing company controls in both UIs. [Company API receipt](../evidence/assets/company-reference.json)

The signed Mac probe reproduced the pinned API cases. After restarting and signing in again, the company list was empty and all 25 remaining assets had no company. The pinned browser UI confirmed prefilled scope editing, append and empty replacement, and retention by default when deleting a company. Turning on asset deletion removed the attributed domain. Use those observations for the SwiftUI comparison. [Company VM and browser verification](../evidence/assets/company-vm.json)

The SwiftUI company editor uses a sheet for creation, scope edits and deletion. Compare the default asset-retention option, prefilled scope, validation, and post-write refresh with the pinned browser. Swift tests cover rule detection, original line numbering, and preservation of saved rule kinds.

The signed Mac app matched the pinned browser for creation, append, prefilled editing, empty replacement and the default retention choice. The Japanese sheet blocked saving an invalid IP and identified its line. The default company deletion retained all 26 assets, while opting in to asset deletion left 25. English screen, keyboard and VoiceOver coverage and server-error UI comparison remain open. [Company UI comparison](../evidence/assets/company-native-ui.json)

The English company check reproduced a language mismatch after changing the language without restarting. The list switched to English, while the sheet rendered in Japanese because it resolved the presentation environment independently. The editor now uses the presenting list's selected locale. The retest switched English to Japanese and back, opened the sheet in each language, then checked duplicate rejection, draft preservation, and Escape dismissal. Keep both directions in future sheet acceptance checks. [Company language and conflict comparison](../evidence/assets/company-locale-conflict-ui.json)

Asset DSL suggestions expose the pinned field, operator and logic groups. The English browser and Mac workflows matched for Return, Down and Tab, and Escape, followed by a one-row exact search. The Mac uses a list below the input and supports click insertion with Japanese descriptions. Swift tests cover the complete field count, operator groups and insertion before an existing suffix. Other populated asset tabs and DSL error presentation remain open. [DSL suggestion comparison](../evidence/assets/dsl-suggestions-ui.json)

Compare invalid DSL and recovery using the same 26 root domains. The pinned browser shows the guest's Chinese parser text for an incomplete expression. The native view classifies HTTP 400 on a nonempty DSL query as a localized expression error and keeps other HTTP failures distinct. Hide the error while completion candidates are open so the user can finish editing. Confirm the error clears when the corrected expression returns its one matching asset.

The signed Mac app showed the localized validation message in Japanese and English for the incomplete query. The corrected query cleared the error and displayed one row in both the Mac app and the pinned browser. [DSL error and recovery comparison](../evidence/assets/dsl-error-ui.json)

The fixed browser and the signed Mac app displayed one synthetic IP, subdomain, application, HTTP service, and endpoint. Address, application metadata, HTTP metadata and endpoint parameter values were visible in the corresponding rows. The browser labels the application tab Application and formats the example port as 443/https. The Mac labels it App and displays 443 https. The pinned browser source renders an HTTP service domain as a link. The Mac displays the domain as text, and service link behavior remains open. [Populated asset comparison](../evidence/assets/populated-tabs-ui.json)

The application tab and port formatting now match the pinned browser. In the signed Mac app, clicking the synthetic HTTP service link handed its registered URL to the default browser. The pinned browser's link uses the same destination. Swift tests verify that invalid URLs, embedded credentials, other schemes, and non-HTTP asset rows do not create a link. [Service link comparison](../evidence/assets/service-link-ui.json)

An isolated comparison returned one synthetic HTTP 500 for an otherwise valid exact-domain search. Both screens exposed the failure, kept the expression, and recovered to one row on Refresh. The signed Mac app distinguished the failure from an empty result and presented it in English and Japanese. The Mac fault was injected at the debug transport boundary. The retry passed through the normal client to the dedicated guest. [Search server-error comparison](../evidence/assets/search-server-error-ui.json)

Asset deletion was applied to the disposable guest, then its successful receipt was replaced by HTTP 500 in each client harness. The fixed browser showed an error with 26 rows and showed 25 after manual refresh. The signed Mac app showed an unconfirmed result in both languages and automatically showed 25 without displaying a success count. The browser interceptor counted one DELETE. The Swift store regression test checked one DELETE followed by a fresh read. [Deletion response-loss comparison](../evidence/assets/delete-response-loss-ui.json)

The fixed browser selected an asset and opened confirmation with Space. The signed Mac app previously focused the asset table with Tab but could not select a row with the arrow keys. The updated table supports Tab, Down and Delete for selection and confirmation. Escape kept all 26 rows and the selection in both interfaces. In the Mac app, Delete reopened confirmation immediately after Escape, and the selected count survived paging. VoiceOver and keyboard confirmation of permanent deletion remain open. [Deletion keyboard comparison](../evidence/assets/delete-keyboard-ui.json)

The asset delete confirmation opened with Cancel focused in the fixed browser and signed Mac app. Tab moved to the destructive action and Space confirmed it. In both environments, the selected synthetic asset was removed and the list refreshed from 26 to 25 rows. [Keyboard confirmation comparison](../evidence/assets/delete-keyboard-confirm-ui.json)

The company table originally took focus without offering a keyboard path to its inline buttons. In the signed Mac build, Tab enters the table, Down selects the company, and Tab reaches Edit scope, Append scope, and Delete company below the table. Space opened Edit scope with the existing rule. After typing a different rule, Escape returned focus to Edit scope and preserved the original. The fixed browser also opened Edit with Space and preserved the rule after Escape. [Company keyboard comparison](../evidence/assets/company-keyboard-ui.json)

Company scope replacement and deletion were completed with the keyboard in the fixed browser and signed Mac app. On Mac, Control-Tab left the multiline scope editor, Tab reached Save, and Space activated it. Tab and Space then confirmed company deletion with the asset-deletion checkbox off. Both environments retained 26 assets and showed the previously attributed asset as unassigned. [Keyboard save and deletion comparison](../evidence/assets/company-keyboard-save-ui.json)

Local inference phases cover metadata and metric contracts, fixed-endpoint runtime verification, isolated VM inference integration, then the shared cloud/local settings and telemetry UI. Compare each phase with the existing browser behavior and verify real Metal execution, model capability checks, context and memory reporting, and tool-call compatibility separately.

### Local inference acceptance tracking

- [x] Decode installed/running model metadata, quantization, architecture context limits and completed-generation metrics.
- [x] Verify a pinned Ollama runtime using Metal on Apple M2 and compare two context sizes.
- [x] Exercise local inference from the signed app settings and retain separate evidence for failed guest boots.
- [x] Verify context-limit rejection before conversation submission using an HTTP fixture and confirm a live runtime still replies.
- [x] Lifecycle state regression tests pass for one dispatch per explicit test, task reappearance and cancellation at admission.
- [x] Verify unavailable/oversized responses, redirect refusal and cancellation before/during a held URLSession request.
- [x] Verify cancellation during an actual Metal inference and VM shutdown.
- [x] Exercise the existing guest agent through a diagnostic local broker, preserving SSE and verifying the pinned guest, loaded context and stopped-log audit.
- [ ] Connect the dedicated VM to local inference with bounded requests, lifecycle cancellation and no arbitrary host destination.
- [ ] Activate a local profile for the existing agent and switch back to a cloud profile in the same settings workflow.
- [ ] Compare the workflow with the pinned browser, including errors, streaming and persistence.
- [ ] Validate representative model families through their runtime capabilities and actual inference. A reported tools capability alone does not prove tool-call compatibility.

API Recon authorization update. The bundled skill matches the browser deployment override exactly. Fresh builds apply it and packaging rejects stale skill declarations. Both local app bundles are updated and signature/integrity checks pass. A signed Cloud Preview guest returned the exact skill through its authenticated API and passed the stopped-log isolation/credential audit. The default guest's fresh boot did not reach readiness, so its API readback remains unverified. Six focused Swift and five Python tests pass. [Update receipt](../evidence/skills/api-recon-update.json)

### Inbound MCP and dual operation

- [ ] Specify tool schemas and the GUI/API/MCP capability matrix, beginning with agent discovery, task creation/start/status/results and stop.
- [ ] Implement the bundled local stdio helper and app-owned IPC broker with client authorization, revocation and generation-bound requests.
- [ ] Connect existing authenticated services, long-running task IDs and idempotent mutations to the shared native runtime.
- [ ] Verify MCP-started tasks in the GUI and GUI-started tasks through MCP, including progress, stop, results and persisted state after restart.
- [ ] Compare the same synthetic task workflows against the pinned browser; test invalid input, lost authorization, retries, cancellation, concurrent GUI/MCP operations and app/VM shutdown.
- [ ] Verify installation and client registration from a packaged app on a clean Mac, and publish connection instructions with the GitHub release.

All MCP implementation and acceptance gates remain open. Direct app operation and MCP operation are both required by the completion goal.

- [ ] Specify external-AI versus ARTEX-agent execution ownership in tool schemas, task state and GUI presentation.
- [ ] Verify useful scoped operations with zero ARTEX LLM profiles, no provider credentials and no local runtime, including restart and retry.
- [ ] Assert zero internal model calls/LLM records and zero cloud/local inference requests in external-AI mode, including configured-provider fallback and agent-trigger negative cases.
- [ ] Verify explicit ARTEX-agent delegation selects its configured model and reports its separate usage; compare both execution modes through the native GUI and MCP.

The signed diagnostic guest verified chat stop and VM shutdown while generated SSE text was still arriving from Metal inference. Both canceled the host exchange, the runtime recorded two cancel operations and idle slots, and no exchange remained active. The stopped guest passed isolation and credential-log audits. This closes the diagnostic cancellation gate; production local-profile integration remains open. [Cancellation receipt](../evidence/llm/local-agent-cancellation.json)

API Recon consent-policy update: copy the latest applied browser override exactly, verify all four permission boundaries and related runtime instructions, rebuild both bundled guests, pin the new cloud manifest, sign both apps and verify authenticated skill readback in disposable guests. [Consent update receipt](../evidence/skills/api-recon-consent-update.json)

Both refreshed app bundles passed signature verification and their disposable VMs returned the exact reviewed skill through the authenticated API. Unauthenticated reads returned 401; both stopped VMs passed isolation and credential-log audits. All 1,160 Swift tests passed with one skip, and five focused Python tests passed.

Inbound MCP implementation checkpoint: the core read broker shares agent discovery and allowlisted task-status services, with authenticated account/VM epoch binding and revocation checks before dispatch and after results. The [capability contract](mcp-capabilities.md) defines metadata projections and separates this from pending stdio/IPC, approval UI, writes, isolated execution and paired browser acceptance. Core tests do not close those integration gates.

MCP local transport checkpoint: the official-SDK stdio helper now reaches the core read broker over a private capability-authenticated Unix socket in a synthetic integration test. Seven socket tests and eleven bounded-stdio tests cover permission rejection, malformed arguments, FIFO/symlink file rejection, concurrent stop/replacement, connection cancellation, frame and queue limits, response credits and terminal partial-output failure. Application-owned startup, native client consent/revocation controls, real-VM/browser comparison and packaged registration remain open. See [transport receipt](../evidence/mcp/local-transport.json).

The complete local regression passed 1,187 Swift cases with one skip and zero failures. The Release helper also passed the actual stdio/socket scenario, including repeated cancellations, overload recovery, 200 unfinished peers and the final exact-Int64 task read. Dependency checkout revisions match all seven committed lock entries. This checkpoint remains synthetic-service acceptance; it does not close native approval, packaged registration or real-VM/browser parity gates.

Native MCP live verification: signed-out permission controls are disabled as intended. A diagnostic launch-order defect was repaired with one-shot launch/runtime admission and three ordering regressions. The signed repaired launch reached the disposable VM, which panicked at state_zero_check before authentication. Preserve that counter-evidence; authenticated MCP UI/VM and pinned-browser acceptance remain open. See [bug record](bugs/native-diagnostic-admission.md).

Kernel fault observation: implement fixed DEBUG-only logging arguments, verify unchanged ordinary configuration and Release rejection, then run one fresh-state preflight against the failed signed-app guest. Preserve failure and hash-bound private evidence; no stability or MCP acceptance claim.

Kernel observation checkpoint: nine focused tests and all1,200 Swift cases (one skip) passed;201 Python checks passed. The single traced default-guest preflight reached fresh auth/401, stopped cooperatively and passed complete isolation/credential audits. Release rejected tracing without creating output; an invalid-artifact control preserved a failed normalized report. Earlier intermittent PID1/kernel failures remain unresolved; this is not stability qualification or MCP acceptance. [Observation](../evidence/mcp/kernel-fault-observation.json).

Outbound MCP acceptance remains required after inbound reads: native server/transport settings, real VM-owned stdio or authorized remote connect/list/call/disconnect, tool refresh, agent assignment, errors/cancellation/revocation/restart and paired frozen-browser comparison. Existing metadata/assignment reads do not close this gate.

Signed MCP native read/consent checkpoint now passes for eight real VM agents, canceled consent, UI authorization, unselected task/write rejection, UI revocation and same-helper rejection. The disposable app exited with Keychain cleanup and cooperative stop; three stopped logs retained all isolation markers and no classified fault. Browser pairing, selected-task success and active-client lifecycle remain open. [Receipt](../evidence/mcp/native-read-consent.json).

MCP selected-task phase: test mode admission and guest seed preconditions first; implement the fixed terminal/no-profile seed and ordinary-service readback; verify one selected task and one denied task via native GUI/helper and pinned browser, including revocation and restart, before recording acceptance.

MCP counter correction checkpoint: the broker now selects authorized task metadata from the real list aggregates; core/IPC tests cover exact counters, omitted/unselected rows, revocation and cancellation. Full Swift1,205 cases pass(one skip); Python211 cases had two shared-build-lock timeouts, both passed sequential recheck. Release Mac and signed default bundle builds pass. The pinned DB/API component verifies all affected sequence rollback and no-model terminal counters. Native selected-task and rendered-browser comparison remain pending. [Counter receipt](../evidence/mcp/task-read-metrics.json).

Login-free startup: implement and test the managed capability-authenticated session endpoint, versioned private bootstrap/artifact gating, automatic ephemeral Swift session, account-free native progress/error/retry flow, legacy-data retention, both guest variants/signatures and actual signed native EN/JA startup. See local-session-design.md; authentication/JWT checks must remain enforced.

Signed disposable local-session service checks passed for both ordinary/cloud fresh and legacy migration cases (eight total boots), including stopped-log secret/isolation audits and data/terminal-task/activity retention. Actual Docker alias cleanup checks pass. Corrected cloud composite metadata matches its executable. UI and deployment remain pending; live-cloud control and candidate fail before confirmed upstream status. See local-session-native-verification.md and bugs/local-session-cloud-egress.md.

November 19 deployment: both signed native bundles passed direct login-free launch and restart. Visible Japanese and English switching passed in the disposable app. After the host firewall permission change, the dedicated diagnostic received invalid-key responses from all four cloud providers. Authenticated inference, repeated reliability and full workflow parity remain open. See local-session-native-verification.md.

Asset deletion confirmation is bound to a fresh list read. The regression cases verify zero DELETE requests from an expired confirmation after search, a same-query reload, or a failed refresh that retains the previous rows. A current confirmation is accepted once. Row, bulk and keyboard actions share the guard, and cross-page selections remain available as in the pinned browser. Sixteen focused tests passed. The full Swift run had 1,229 passes and one skip. The signed disposable native run reached guest readiness but stalled during fixture preparation and was stopped before visual verification. The native and paired browser UI rerun remains open.

November 25 asset review: sampling identified a blocked checkout file open during preparation. The asset-only Debug review now reads a digest-checked seed from the signed app bundle and verifies the 26 synthetic domains through the authenticated asset API. On the signed Mac app, page selection opened a confirmation for all 26, Cancel retained all rows, an invalid search disabled bulk deletion, and clearing it restored the list and button. The private VM stopped and the temporary Keychain item was removed. The prior fixed-browser receipt covers Cancel and retention. A fresh side-by-side browser run remains pending. [Verification record](../evidence/assets/selection-confirmation-native.json)

To repeat the asset review, copy a Debug bundle with a verified guest and place `script/asset_catalog_seed_guest.py` in `Contents/Resources/Diagnostics/` before signing the copy with the virtualization entitlement. Verify the signature and launch it with `--native-diagnostics NEW_PRIVATE_DIRECTORY --native-review --no-llm-review --asset-catalog-review`. Wait for `native-review-ready.json`, check Assets → Root domains, then create `native-review-finish` in the new directory to release the fixture.

November 25 pinned browser comparison. A fresh disposable reference at the fixed source commit rendered the same 26 domain names as the signed Mac fixture. In both UIs the bulk dialog named 26 records, Cancel started focused, and cancelling retained all records. An invalid search displayed an error in both UIs. The browser kept bulk deletion enabled during the error, while the Mac disables it until the search is valid. Clearing the input restored the 26 rows and bulk action on both. The browser run used a locally available Chromium 124 image by digest and the same pinned backend binary. It ran in English and the Mac in Japanese. This comparison exercised cancellation only. Company server errors, VoiceOver and the remaining asset states stay open. [Paired verification record](../evidence/assets/selection-confirmation-comparison.json)

Company scope response loss. The fixed browser successfully replaced one synthetic company's scope, then received an injected HTTP 500 in Chromium. It kept the draft, sent one scope write and showed the replacement after manual refresh. The signed Mac diagnostic threw the equivalent error immediately after the real VM acknowledged the write. The Japanese editor kept the draft, reported that the result was unconfirmed, disabled a second save and showed the saved scope after the sheet closed without a manual refresh. A separate refresh confirmed the same scope and the diagnostic counted one successful replacement. Only the disposable Debug copy had the fault injection. The VM stopped and the temporary Keychain item was removed. Other company error paths and VoiceOver remain open. [Comparison record](../evidence/assets/company-scope-response-loss-comparison.json)

Company removed during editing. After the editor opened, a separate authenticated request removed the lone synthetic company while keeping its assets. The pinned browser and signed Mac diagnostic both received an actual HTTP 404 on scope replacement. Both showed that the company was missing and kept the draft. The browser removed the stale row after manual refresh. The Japanese Mac editor disabled resubmission and refreshed the list automatically. After closing the sheet, the company count was zero and all 26 root domains remained. The temporary Debug fixture used a separate trigger and observed the HTTP status without replacing it. Swift tests cover append, replace and delete classification, the existing duplicate and invalid-input paths, uncertain outcomes, and English and Japanese message lookup. Full local results were 1,232 Swift and 222 Python passes with one Swift skip. [Comparison record](../evidence/assets/company-missing-comparison.json)

Logs phase 4 now reads the authenticated recent and historical GET routes from SwiftUI. It polls every two seconds, keeps an exclusive history cursor, bounds the displayed rows and preserves literal log text. Pause consumes the live cursor without showing arrivals. Clear empties the screen without changing saved logs. In the fixed browser, keyword filtering, pause/resume and clear worked, and the historical API still returned rows after clear. On a signed Mac diagnostic, the keyword and warning filters, pause/resume, clear and English/Japanese state retention worked. Reopening the view read the same 11 logs again. The ordinary guest timed out at the blank check, so the Mac screen test used the existing reviewed private static-checker diagnostic guest. There were 1,237 Swift passes and one skip. Actual populated-history comparison with identical fixtures, burst/reconnect behavior, rendered errors, keyboard/VoiceOver and Release runtime parity remain open. [Comparison record](../evidence/logs/native-logs-first-comparison.json)

Populated Logs history. An isolated fixed browser and the signed Mac Debug app used the same 350 synthetic rows. Native restart restored 100 recent fixture rows and the older pages returned another 200 and 50. The fixed browser and native authenticated APIs produced the same full ordered digest covering database IDs, levels, timestamps and literal messages. Both UIs found the oldest row after two older-page actions. The Mac showed the oldest nine in ascending order and hid the older button when the history was exhausted. Its counters also included ordinary startup logs. The Mac used the existing static-checker diagnostic guest with Docker Desktop stopped. Swift reported 1,238 passes and one skip. Live burst/reconnect behavior, keyboard/VoiceOver and Release acceptance stay open. [Comparison record](../evidence/logs/populated-history-comparison.json)

To rerun the native fixture, add `script/log_history_seed_guest.py` to `Contents/Resources/Diagnostics/` in a private signed Debug app copy with a verified guest. Launch with `--native-diagnostics NEW_PRIVATE_DIRECTORY --native-review --no-llm-review --log-history-review`. Wait for `native-review-ready.json`, filter Logs for `Log history fixture 001`, load older logs twice, then create `native-review-finish` to stop the fixture.

Logs burst recovery. The pinned Go backend retains 3,000 recent rows and returns the latest sequence even when its ordinary page omits earlier rows. After a confirmed snapshot, the Mac poll compares that sequence against the last accepted cursor and requests the full ring once when there is a gap. It retains a readable tail when widening exceeds the existing JSON transport limit, reports any unresolved gap in English or Japanese and clears the notice when the display is cleared. Controlled transport tests covered 1,200 entries after a disconnect, cursor zero after an empty snapshot, retry after a failed expansion, ring overflow and the byte limit. Docker Desktop stayed stopped. Real VM burst and restart comparison, SSE reconnect, and the remaining UI acceptance checks stay open. [Verification](../evidence/logs/recent-burst-recovery.json)

Logs SSE transport proof. Over the existing isolated VM socket, the signed Debug app read eight events from the fixed authenticated SSE endpoint, then opened a second connection from a nonzero cursor and read eight more. Event sequences and text matched the authenticated recent endpoint. The bounded reader delivered before EOF in socket tests and verified fragmented headers and frames, heartbeat handling, HTTP 401, and framing bounds. Docker Desktop stayed stopped and the fixture VM stopped cooperatively. Swift recorded 1,246 passes and one skip, and Python recorded 222 passes. The log screen still polls. Continuous production delivery, reconnect during a burst and browser/native rendered comparison remain open. [Verification](../evidence/logs/sse-vsock-replay.json)

The normal Logs screen now follows the authenticated SSE connection after reading its initial snapshot. It returns to the bounded recent endpoint after a disconnect or sequence gap and reconnects from the accepted cursor. The same cursor survives Clear and advances during Pause. In the signed Debug app with the isolated diagnostic guest, opening Logs left one owned stream socket and switching to Dashboard closed it. Socket tests verified a second event arriving after the first was delivered and while the connection remained open. Controlled cursor tests covered duplicate rows, sequence gaps, replay and display actions. Docker Desktop was stopped. Fixed-browser comparison during a live burst, VM stop during an active stream, keyboard and VoiceOver remain open. Swift recorded 1,247 passes and one skip. The Release app and its helper passed local signature verification. [Verification](../evidence/logs/live-sse-view.json)

Cooperative VM stop with an active log stream. A signed Debug fixture received events through the same authenticated stream used by the Logs view before requesting shutdown. The stream reported cancellation and released its owned socket, and the virtual machine stopped. After restarting the same disk, a fresh authenticated session recovered all 350 fixture rows across recent and history, then replayed eight events and resumed for eight more. In the Japanese native window, Logs opened with 108 recent rows and established one stream. Switching to Dashboard closed it. The diagnostic VM shut down and its temporary Keychain item was removed. Docker Desktop stayed stopped. Browser comparison during a live burst and the accessibility checks remain open. [Verification](../evidence/logs/live-sse-vm-stop.json)

Heartbeat recovery for a dropped log tail. The signed Debug app received a real heartbeat from the pinned guest over the authenticated VM socket. A separate socket test delivered a heartbeat between two events while the peer stayed open. The store regression test simulated two missing final notifications and confirmed that the heartbeat triggered a bounded recent read from the last accepted sequence, recovered both rows and kept the stream open. Docker Desktop stayed stopped. Comparison of a live burst and reconnect with the fixed browser remains open. [Verification](../evidence/logs/heartbeat-catch-up.json)
