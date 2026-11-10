# Architecture

Decision: SwiftPM multi-target application, SwiftUI/AppKit desktop shell, Virtualization.framework host controller, Linux ARM64 guest. Final UI is native, never a hidden browser frontend. Phase 1 boots a minimal checksum-verified guest with zero network, storage or host shares and proves serial readiness. Artifacts are pinned with SHA-256 and verified before boot.

Modules: ArtexCore (feature catalog, lifecycle state machine, integrity checks, transport contracts); ArtexMac (native views and app-owned VM service); VMProbe (signed headless real-VM acceptance runner). Views do not invoke process shells. VM state is app-wide and updated only on the main actor. Resource files are application-owned, read-only inputs. Logs use bounded buffers. Fatal boot and shutdown errors remain visible.

Planned Phase 2: immutable guest system image plus writable ext4 data disk; root-owned PostgreSQL process and non-root ARTEX service; no host shares; explicit vsock ports for typed app/guest API transport with per-session authentication. No arbitrary command endpoint on the host. Network policy needs separate design and negative tests before enabling it; initial proof has no network device. Do not expose guest services to the LAN or reuse browser credentials silently. Keychain holds native session/secret material; guest DB secret handling must match equivalent browser behavior and access controls.

Update design: application and guest-image versions are a pair recorded in a manifest; verify source/artifact digests, stop service, make coherent data backup, replace immutable image, verify health, rollback image on failure; never roll a migrated database backward without a tested backup restore. Use Apple-supported graceful guest stop and a separately labeled force-stop path. VM boot/transport success is necessary but insufficient for UI parity.

Research: Apple Running Linux in a Virtual Machine, VZLinuxBootLoader, VZVirtioSocketDevice documentation. Browser source navigation, 21 features, all page routes/API handlers captured mechanically. Live fresh /system/llm confirms current reference version and model cards/tabs. Lazyweb Agentic Search d85df937-aa86-420d-ad7f-e702652210e7 returned Commandbar and Fingerprint dashboard/status references; finalization hit account rate limiting. Apply stable navigation and clearly separated health, activity and settings; avoid replacing upstream workflows with decorative dashboards.


Localization decision: en/ja locale model plus persisted native preference, shared String Catalog resources and locale-aware typed presentation of builtin defaults. Synchronize new backend system-output language through its existing authenticated output_language setting; replace ja-only guest bootstrap default with validated preference during the localization phase. Preserve immutable baseline and arbitrary user content. Unknown locale falls back to English; an unsupported persisted backend locale must be migrated explicitly to the chosen supported preference. Han characters alone cannot distinguish Japanese from Chinese; use phrase/catalog provenance, not broad CJK deletion. See localization-audit.md for current findings and acceptance matrix.


L1: AppLanguage(Codable, CaseIterable, Identifiable, Sendable) contains en/ja with stable native self-names and Locale projection. AppLanguagePreferences is MainActor observable with injected UserDefaults; only its namespaced language key is read/written. Fresh system preference matching accepts regional en-/ja- and underscore forms; persisted values require canonical exact en/ja. A bad stored value is not confused with an absent choice and repairs to en. Select accepts typed values only. UI/String Catalog/backend synchronization remain subsequent ordered gates; Lazyweb is outside this core preferences-only stage.


L2: English-source String Catalog processed by ArtexCore SwiftPM resources (defaultLocalization en). AppStrings exposes typed shell keys and explicit-locale lookup with English fallback; feature IDs map to typed localized titles, not translated user data. ArtexMacApp retains one AppLanguagePreferences in State and passes it into RootView; bind a menu Picker in the toolbar with stable self-names, apply locale without language-keyed .id or runtime recreation. Root labels use the shared catalog. Browser settings/page.tsx:124/665 is the pinned behavioral basis: instant UI change, separate backend update failure. Backend synchronization remains a subsequent explicit gate. Lazyweb search76693227-6d1e-45bf-9de0-c269b458b639 returned language-settings selection metadata (Amazon/Freevee); metadata-only corroboration, not screenshot proof. No hosted report requested.


L2 CI correction:40110609236 proves hosted SwiftPM copies xcstrings without compiling, unlike local Swift Build backend. Keep String Catalog authoritative; generate checked-in UTF8 plist .strings in en.lproj/ja.lproj and process those portable resources, exclude raw catalog from runtime resources. A strict standard-library exporter accepts only current simple translated stringUnit schema and supported locales, rejects unsupported variations, and --check compares deterministic generated bytes. CI and signed-build wrapper run --check before Swift build/test. Direct swift test uses committed derived resources. No hand-maintained duplicate translations.


L3 uses existing locale environment, typed AppStringKey chat entries in the single catalog and generated portable resources. Views resolve display-only strings with no language .id. AppKit representables update title/help/accessibility on the same control; editor language updates must not touch text, selection or marked text. Picker labels use locale at creation, preserving captured owner callback. ChatUploadPresentation gains a language argument defaulting to its existing Japanese API for prior callers, production passes locale explicitly. BuiltinAgentText matches known key plus exact UTF8 default value from pinned db/db.go; no server writes or blanket script conversion. Existing arbitrary errors, default-title provenance and backend templates remain pending. Lazyweb38aa7a86 search chat composer file attachment controls yields moderate Skype metadata only; existing pinned composer and A5/A6 screenshots are authoritative; no visual proof inferred from metadata.


L3 title safety discovery: pinned conversations.go:74/493 treats empty/Korean default title as the auto-title sentinel. Explicit localized creation titles would suppress first-message auto-naming. The proposed creation-title tests were withdrawn before any production implementation/checkpoint; do not count that missing-API probe as a valid product RED. Keep wire/default/auto-title semantics unchanged until a backend provenance-compatible migration is designed; never bulk-rewrite existing custom titles.

L4a error foundation: replace native static validation payload strings with typed BackendValidation values and a bilingual error presenter. Preserve existing Japanese LocalizedError compatibility during staged store migration. Explicit language lookup must not inspect OS preferences or stringify unknown errors. Status/Keychain numeric codes may be interpolated, but arbitrary server bodies/paths/secrets must never be presented. This infrastructure stage does not close UI error switching or R8.

L4b Chat errors: store safe typed AppErrorMessage values, render at current view locale without replacing views, issuing requests or mutating draft/attachments/selection. Keep computed Japanese String compatibility for diagnostics/old tests. Cover list/history/send/stop/workspace/upload/partial-delete/mention pagination/body/details; preserve cancellation/generation/owner checks. Unknown errors reduce to a typed fallback without retaining raw data. RED/GREEN store tests, full regression, reviewer, signed build, then actual native/browser failed-send locale comparison are distinct gates. Lazyweb query chat error retry message returned weak adjacent DoorDash metadata (similarity.385), not visual proof; existing fixed error UI remains authoritative.

L4c migrated screen error/notice gate: AuthenticationSession, LLMStore and DashboardLoadState retain AppErrorMessage identity, with Japanese computed String compatibility. LLM confirmed notices retain catalog keys, independent of failed refresh; resolve error/notice text at current view locale in auth, LLM settings/editor/rotation and dashboard. No locale-triggered authentication/mutation/poll reset or password/API-key persistence. Keep forms, terms agreement, generation and last-good data unchanged. Surrounding untranslated controls and terms language remain separate gates. Tests cover validation, unknown-error sanitization, confirmed-save/failed-refresh and cached-dashboard preservation. Lazyweb settings inline validation error returned weak adjacent Gopuff captcha metadata(.356), not inspected visual evidence. Actual native/browser switching remains deferred until user unlocks Mac.

L5 authentication/terms: translate all native auth labels via typed catalog; load both pinned terms documents once with a typed AuthTerms.loadAll API and resolve current locale in the existing sheet. Preserve password/confirmation/agreed/focus bindings, task identity, submit behavior and phase-clear boundaries. Follow pinned browser read gate: reset per sheet opening, preserve readToEnd within the open sheet across locale changes; no new language-keyed view identity. Full28-entry terms documents must exactly match fixed auth.terms per locale; no legal-content rewriting or runtime network. Native-specific automatic setup-token handling and fixed username keep accurate native instructions. Resource/API tests RED/GREEN, review/full tests/signed resources; live native/browser controls/scroll/read gate remain pending until Mac unlock. Lazyweb terms agreement modal: moderate Postman metadata(.479), not inspected visual proof.

L5 adjacent read-gate repair: initial empty scroll geometry must not grant read completion before a document is loaded. Track a safe per-sheet reading progress and include documentLoaded in the Equatable viewport observation so a newly loaded short document can become readable even if atEnd remains true. Failed/empty documents cannot enable Agree; loaded document end latches within open sheet across locale, fresh sheet starts unread. This is a functional read gate, not stronger login authorization; the existing explicit agreement checkbox remains unchanged. Separate RED/GREEN and deferred actual scroll comparison.

L6 LLM UI: migrate settings/cards/editor/model picker/rotation/global retry/numeric validation/help to typed en/ja catalog. Add single-pass named placeholder formatting so opaque model names, masked key hints and values cannot be recursively reinterpreted as template tokens. Preserve tags/raw API enums/prefix keys/bindings/invalid text/dirty flags/sheet ownership and existing fieldGeneration only on confirmed reload/save. No locale id/task or network/mutation changes. Research Lazyweb AI model provider settings returned moderate V7 metadata(.535), not inspected visual evidence; fixed LLM browser remains reference. RED/GREEN catalog/format tests, full regression/review/signed bundle; actual native/browser switching stays deferred by user Mac unlock.

L7 Dashboard UI: localize headings, groups, empty/stale/loading states, selectors, chart axis/series/legend/accessibility, summaries, period counts, asset/traffic/system panels. Keep metrics/calculations/date identities/queries/polling/selection IDs/tags/navigation unchanged. Known task/engine/severity labels match pinned status dictionaries; exact raw identifiers only, unknown text preserved. Activity types localize known5codes while custom tool names/workers/summaries remain literal. Chart series and legend scale use matching localized keys; color/selection parity needs actual UI. Reuse single-pass opaque formatting. RED/GREEN resource/status/metric invariance tests, review/full tests/signed resources; native/browser remains deferred until unlock. Lazyweb usage analytics dashboard: strong Google Analytics metadata(.631), not inspected visual proof; fixed browser is authoritative.

L8 runtime/parity: translate controls, six lifecycle states, sidebar status and feature-comparison table/counts at current locale. Preserve nativeStatus gate, feature IDs/browser paths and unknown feature titles. Store a safe AppErrorMessage alongside existing raw diagnostic strings in VMController/DesktopRuntime; clear it at the same start boundary, set it only in existing fail/catch boundaries. RuntimeError classes map to safe catalog keys, never interpolate arbitrary stage/path/detail; unknown framework errors get a runtime-specific fallback. No VM config/capabilities/protocol/state transition/auth/disk/poll changes. Keep raw guest logs and CLI diagnostics unchanged. RED/GREEN resource/state/failure boundary tests must not launch a VM; review/full tests/signed resources. Actual native/runtime controls and standard OS menus remain pending; SwiftUI locale alone does not localize standard AppKit menus. Lazyweb virtual machine status settings returned weak adjacent Height metadata(.383), not inspected visual proof.

L9 menu boundary: retain existing NSMenus/actions/responder chain/shortcuts/targets/enablement. Translate only recognized native action+known static title pairs; registered window/help/services menu identities and guarded root header names identify standard groups. Unknown/custom/attributed/custom-view items and dynamic window/service names stay literal; do not rebuild menus. Update from app language and at AppKit didBeginTracking, resolve current main menu each time (SwiftUI may replace it). One selector observer with explicit stop; no timer/action invocation/persistence/VM changes. TDD synthetic-menu metadata/roundtrip/unknown and observer replacement/stop tests plus28-key catalog; actual OS menu dispatch and all dynamic/unknown coverage remain pending until unlock. Lazyweb desktop application menu bar returned weak adjacent Cluely metadata(.340), not inspected visual proof. Use the narrow AppKit interop boundary per installed skill; SDK NSMenu notifications and NSApplication registered-menu properties checked locally.

T1 Tasks finite core follows tasks-core-design.md: all current create options plus list/detail/metadata/control/batch/delete, strict identity and mutation outcomes, bilingual typed validation; no active selection side effect, no UI completion claim. RED/GREEN/full regression/review/signed build precede real VM/reference and UI acceptance.

T2 Tasks state follows tasks-state-design.md: observable list/detail read states and selected ID, race/lifecycle guards, explicit confirmed/rejected/unconfirmed mutation outcomes for all finite T1 operations, retained confirmation across refresh failure, no automatic mutation retry or active selection,10-second cancellable polling. No screen/feature/runtime acceptance. Backend state only; Lazyweb out of scope. RED/GREEN, controlled response-order/cancel/reset tests, full regression, review and signed build required.

T3 follows tasks-ui-design.md: wire native list/detail, search/status/sort and finite rename/pin/control/delete actions to the retained per-window T2 store, authenticated routes and dashboard task navigation. Bilingual controls, safe uncertainty and five default-off cleanup flags; no language-driven view replacement. Feature becomes in_progress only. Creation, categories/archives/bulk/advanced detail and runtime comparison remain required later. RED/GREEN presentation/controller/layout tests, review/full regression/signed build; actual native/browser comparison deferred until unlock.

T4 follows tasks-create-design.md: implement creation option catalogs and all12T1body fields in native form with ordered profiles, source/company/category selectors, template application and stable rule rows. Captured context IDs guard all inputs, async loads and submit/close. Creation is explicit once; confirmed clears even if refresh fails, unknown retains draft and blocks resubmit. Native attachments/template/category management and whole-task/runtime/UI parity remain open. RED/GREEN, controlled race tests, full regression/review/signed build; actual comparison after unlock.

B1 boot diagnostics follows boot-preflight-design.md: separate blank/nonblank from scan execution failure, preserve fail-closed formatting, add private one-boot read-only VMProbe preflight with fixed sanitized report. Use only fresh disposable state and verified separate candidate; no user-data/guest-policy change. TDD/report/guard tests, controlled old/new-profile single experiments, review/full regression/signed build. Kernel reliability/root cause and visible parity remain open; no Lazyweb for infrastructure.

T5 staging transport follows tasks-staging-design.md: authenticated finite UUID staging upload using existing bounded multipart/vsock transfer and session revision/progress guards. Validate exact guest draft paths and preserve raw Unicode; never turn guest paths into host URLs. TDD malformed/status/count/stale-auth/cancel/header tests, review/full regression/signed build. Creation-model/UI/description manifest and actual VM/browser upload acceptance remain next gates; no UI work or Lazyweb in this transport phase.

T6 follows tasks-staging-ui-design.md: connect T5 transport to retained creation draft ownership, explicit selected-file picker, cancellable progress and exact en/ja browser manifest. Preserve text across close, rotate draft on discard/reset/confirmed create, guard stale operations and block submit during upload/picker. TDD and review/full regression/signed resources; no actual UI parity until unlock.

T7 follows task-staging-runtime-design.md: bounded one-boot actual staging/upload/download collision exercise on a fresh private source-kernel candidate, compared with a fresh pinned Docker reference; no agent/task/conversation/cloud or user data. Fixed synthetic fixtures, normalized full-log audit and preserved failures; TDD/negative fixtures/review/regression before hardware. UI/OS-picker/restart reliability remain separate open gates. Infrastructure only; Lazyweb out of scope.

T8 follows task-template-management-design.md: full native template manager (list/new/create/edit/delete, category and interception rules), save-as seed from creation, safe uncertainty and captured ownership, en/ja labels. Source contract/negative tests RED/GREEN, review/full regression/signed resources; actual OS/UI/live workflow comparison stays open. Fixed baseline and VM isolation unchanged.

T9 follows task-category-core-design.md: finite category CRUD and assignment service; explicit null, validated schema/ownership/partial receipts, no agent activation. Native manager and full UI/runtime comparison remain required.

T10 follows task-category-ui-design.md with a retained per-window category workspace, typed receipts into task store and creation, context/editor/decision/lifetime tickets. No locale-driven reconstruction.

T11 follows task-catalog-runtime-design.md: finite injectable production-client exercise, one-boot safe report and private memory-vault provisioning, complete stopped-log audit and explicit terminal success. Preserve failed disks/logs; no default-image promotion or retry-until-green.

T12 follows tasks-bulk-design.md: retained window-owned bulk workspace and immutable context snapshots share the TaskStore external mutation gate with category operations; pure confirmed projections do not activate agents. Captured epoch/dialog IDs guard bindings, sequential deletion and progress; unknown-ID block requires explicit acknowledgement.

T13 follows tasks-archive-core-design.md: bounded finite service/direct decoding, safe error/warning presence projections, typed en-ja state/phase labels and separate acceptance semantics. Permutation validation honors source topological ordering.

T14 archive state requirements: retained paginated/search/state reads, page-local checkbox selection, single-flight two-second polling, selected-detail ownership, and accepted-restore identity reconciliation. Only a detail404 for a captured accepted restore may notify live-task refresh; page disappearance, unrelated404, failed reads and stale sessions cannot. Stop retains pending receipts; authentication reset clears them. Native tabs/actions/runtime parity remain subsequent gates.

T15 archive action requirements: capture explicit single/batch archive, restore, permanent delete and failed-state retry contexts; share exclusion with TaskStore category/bulk/ordinary operations and archive reads.202means accepted only, no optimistic deletion/restoration. Reordered partial batch receipts remain per-ID, never auto retry uncertainty. Capture unknown task/archive identity sets with explicit acknowledgement; cancellation/reset/stop must not unlock in-flight writes prematurely. Native UI and real-job/browser acceptance remain required.

T16 archive UI requirements: native live/archived tabs, server search/state/page20 with10/20/50sizes, page checkbox selection, nine reference columns, typed progress/error/warning summaries, restore/delete/retry per-row and bulk, captured confirmations with permanent-delete totals, en/ja outcomes and unknown acknowledgement.202is queue acceptance only. Restore reconciliation triggers live data refresh; tab/read lifecycle survives locale/sidebar and resets on logout. Real keyboard/AX/visual/runtime parity remains required after unlock.

T17 archive runtime requirements: fresh disposable state only, fixed terminal tasks and exact synthetic bytes seeded without normal createTask/launchTask, bounded native API archive/restore/delete checks versus pinned reference, same-disk restart durability, no live profiles/LLM/agents/host commands. Split prerequisite fixture boundary verification (T17a) from actual VM/reference operations (T17b); neither alone closes runtime acceptance. Preserve failed experiments; never promote kernel candidate by a single run.

T17b Core exercise contract: required guest-only fixture control for quarantine/repair of the ready archive for fixed task7101 plus zero-agent audit; bounded120polls/45sec stage budget, no automatic write retry. Phase2 proves initial terminal rows/files, bulk archive, deliberate restore_failed then explicit retry, restored exact metadata/files, second delete and first rearchive checkpoint. Phase3 consumes same-disk checkpoint and proves persisted ready archive and final restore/files/second deletion. Injectable clock/sleep and fake fault control are unit-test dependencies, not runtime evidence. Probe/reference/hardware integration still required.

F1 follows findings-core-design.md: typed finite read/triage/delete contracts only, with all advanced Findings workflows retained as later required gates. Infrastructure only; Lazyweb out of scope. No feature/UI/runtime acceptance from Core tests.

F2 follows findings-state-design.md: owned finite read/page slots and retained Findings workspace, cross-page export selection, captured mutations with conservative uncertainty across4xx/stop/reset, no automatic replay. Backend state only; Lazyweb out of scope.


F3.1 follows findings-screen-design.md: retained window coordinator, captured view/session/unknown revision, no replay, bounded preference storage excluding search/cursors/private drafts. Lazyweb metadata and fetched table practice inform subsequent native list/detail controls.


F3.1 separates unsent edit draft lifetime from immutable confirmation ownership. See findings-screen-verification.md and bugs/findings-screen-draft.md. No UI or runtime acceptance is inferred from 13 coordinator tests.


F3.2: native split list/detail, asset source-list with iterative raw-UTF8 keyed expansion, explicit filters and bounded page sizes. A gate-aware coalescing read coordinator schedules latest owned queries without cancelling same-query asset tree on scope/page changes. Separate stats/view five-second loops retain F2 semantics; owner-captured bindings reject stale callbacks. RootView owns the coordinator per authentication identity. Lazyweb desktop issue-list search9599af57-1296-4997-8ef8-aca8713d1a4a yielded adjacent aboard/linear metadata (top0.511), not inspected screenshots. Existing fetched table practice and macOS split-inspector guidance inform structure; pinned browser controls remain authoritative.


F3.2 repairs separate callback lifetimes: managed polling waits retired cleanup, detail callbacks use selection revisions, search uses session/raw draft/control-gate identity, and dialog getters are captured. Coalesced reads retain same-query asset snapshots. See findings-ui-verification.md and bugs/findings-ui-lifecycle.md.


F4 follows findings-runtime-design.md: F4a finite transactional seed with no arbitrary inputs, then F4b bounded native/reference reads, mutations and same-disk durability. Preserve browser8787/kernel counter-evidence; no source/default promotion or host command interface. Backend-only: Lazyweb out of scope.


F4a uses transactional ALTER SEQUENCE RESTART, with explicit postcondition rollback witness; setval is not suitable for this atomic seed. Full runtime DDL includes schema.sql plus llmUsageSchema and llmRecordsSchema/Migrate. Exact33 trigger-created system asset links are part of the expected fixture. See findings-seed-verification.md and bugs/findings-seed-atomicity.md.


F4b uses a bounded typed FindingExercise with hard request/deadline/cancellation gates and an injected fixed no-agent auditor. Before-restart operations produce a typed checkpoint; a fresh runner verifies persisted final values and deleted nodes after restart. A DEBUG-only guest fixture client/probe seeds and audits existing authenticated guest script route; independent reference runner derives same normalized report. Three boots are needed: seed fresh DB, restart to hydrate task context and mutate, then restart to verify durability. Source server.go2396-2431 commits status before later name errors, so owned fixture status+NUL-name can witness partial commit without a general fault command; verify actual result before accepting it. Status notifications may create internal events, but no channels/deliveries/agents may be configured or run.


Unassigned-asset presentation: identify key__none__ +kindnone, not Han/Hangul content. Use a dedicated en/ja catalog key for visible/accessibility labels; keep raw DTO bytes and every other label unchanged. Lazyweb desktop asset-tree/empty-state search5c779906-437c-40e4-bb84-be6d9ca0d576 returned Hygraph asset metadata(top0.562), no inspected image; pinned source remains primary evidence. No new layout.


F4b CI repair: extract seed-to-wire conversion into an explicitly typed test-only helper; use short statements and typed asset mapping, preserving raw values and one canonical wire key. Product code and fixture SQL remain unchanged.


Use small typed fixture aggregate verifiers and checksum-bound initial/final JSON expectations. Match exact UTF8 labels/names/descriptions, known metadata, sorted task/group/node identities, severity buckets and timestamps. The existing bounded transport remains shared by the eventual full exercise. Keep gate count128 and90sec pre/post response checks, no retries.


Reference math derives expectations from fixed SQL seed values independently of Swift and its aggregate JSON. A finite Findings-only client uses128calls/90sec pre/post checks, no mutation retry. Compare100initial reads, shared edit/status/partialHTTP500/readback/delete checks, and100persisted reads. Keep native-only cache/selection/uncertainty acknowledgments outside the shared projection. Bind completed VM logs/boots and reference lifecycle plus identical backend/seed/audit digests before accepting comparison.


Use a separate seven-request boundary stage: GET9101, name-only, class-only, severity-only, empty-name,8192-byte class, restore three original fields. Verify every response against full independent expected row, so unrelated fields cannot change. Ordinary mutation stage stays14 requests; outer initial100+boundary7+mutation14+postaggregates2=123 within128/90sec. Add post-boundary audit, bump checkpoint to schema2 with typed boundary receipt; after-restart remains100. Independent reference compares six remote boundary checks; native local-validation receipts stay separate. Keep previous schema1 evidence historical.


F5 follows findings-advanced-design.md: typed bounded traffic reads first, then mutations/state, lineage/retests/deepen/report, real-byte exports and native UI plus actual guest/browser acceptance. F5a has no UI, host-write, networking or agent activation changes.


Implement F5b state per findings-traffic-state-design.md before native evidence controls. Use existing generation-owned reads, per-window selection/session/activity and locally prepared fixed requests. State controls do not change guest capabilities.


Audit and repair the existing FindingStore handoff boundary per findings-mutation-handoff-design.md; keep public service API and backend contracts stable. Task/LLM audit remains distinct.


Task handoff recurrence repair follows task-mutation-handoff-design.md; actor-owned direct tickets and guarded shared lease acquisition retain public contracts. External later-dispatch and LLM remain separate gates.


External category/bulk/archive boundary repair uses a typed developer-only request handoff marker and lease validation per task-external-handoff-design.md; no serialized execution or UI layout change.

## Investigation harness extension

User-requested goal: integrate Dirsearch, Fscan, Masscan and SoftEther VPN through native task controls while retaining guest-only execution, explicit target/network policy, evidence provenance and English/Japanese UI. Implementation is pending. See [design and acceptance phases](investigation-harness-design.md). This extends rather than replaces browser parity and release requirements.

## Cloud provider extension

Support OpenAI, Anthropic, Gemini and Groq with model discovery, streaming and guest-only local tool calls. Preserve existing custom endpoints and protocol variants. Acceptance requires all four providers to work from the Mac app through the isolated Linux VM. Gemini and Groq have profile presets and fixture coverage. Live API and UI acceptance are pending. See [the four-provider plan](cloud-providers-design.md).

Tool-run history uses authenticated GET /api/commands and
GET /api/commands/stats. The list uses zero-based pagination. Both
requests share the normalized keyword and exploration ID. The wire
parameter is named `task`, but the backend matches `exploration_id`.
The list's page and size are absent from the summary request. Treat
recorded input and output as text. Bind list and summary results to
their filter generations so late responses cannot replace newer
selection. The Mac screen follows the pinned browser's table columns,
input preview, detail and separate summary. Lazyweb's Front audit-log
reference informed the placement of filters above the table and the
status column. Mac applies filters on Enter or Apply Filters and shows
read failures separately from empty results.

LLM call history reads `GET /api/llm/records`, `GET /api/llm/records/tasks`, and `GET /api/llm/records/{id}` through the authenticated VM transport. The list starts at page zero and offers 25, 50 and 100 rows. The model and task filters are exact values and the session filter is trimmed before the backend substring match. Decode the numeric record ID as Int64. Fetch the optional bodies only when a row is selected and keep the source text intact. The existing finite transport imposes its 4 MiB response bound. In the UI phase, scope detail results to their selected row and present transport errors separately from empty results. Read back the recording preference after an update. Require confirmation and readback for task deletion.

The history recording switch sends only `llm_record` in `PUT /api/settings` and displays the value returned by a fresh GET. Task deletion sends the exact confirmed identifier to `DELETE /api/llm/records?task=…`. Reject identifiers the backend would change by trimming. Refresh the list and task counts after each deletion attempt because an error may follow a committed write.

The Assets screen reads six inventory types from the pinned `GET /api/assets` contract and reads counts separately from `GET /api/assets/counts`. The browser uses offsets and 25, 50, 100 and 200 rows. Preserve the search expression as a single encoded DSL query parameter and let the guest validate its grammar. Keep optional row fields and identifiers typed. Company management, deletion, and the SwiftUI comparison follow the read service.

### Asset deletion boundary

Send positive, distinct 64-bit asset IDs to the authenticated guest in the pinned DELETE JSON format. Bound request size and validate that the confirmed deletion count is between zero and the number of IDs sent. The service sends once. The later UI must reconcile with fresh reads after an interrupted request, which may have been applied by the guest. Test the body, partial receipt and invalid receipt at the transport boundary before wiring confirmation and selection.

The asset table uses explicit row selection, a page selection control, and an individual delete action. Selection remains across pages in the same asset tab. The confirmation captures the selected IDs and states the number of records and the permanence of the operation. The design follows the pinned browser behavior and uses the separation between selection and destructive confirmation seen in Lazyweb's Confluence example. The Mac view reports the server count, refreshes after every dispatched attempt, and clamps the page if the last page disappears.

Use the authenticated asset catalog client for structured company scope writes. Enforce the pinned server's request and raw rule limits, require HTTP 201 for creation, and preserve HTTP 409 for duplicate names. Scope addition can partially succeed. Replacement can clear all rules with an empty array, and the server rejects invalid replacements atomically. Require a confirmed company deletion receipt and honor the explicit asset-deletion flag.

The company scope editor follows the pinned browser's one-rule-per-line input. Saved lines keep their stored kind so editing or reordering a keyword that resembles a domain cannot change its attribution behavior. Show invalid line numbers before dispatching. Lazyweb's Attio and Retool references inform the visible add action and an editor attached to the list context.

Asset DSL completion uses the fixed browser's field order and operator groups on all six searchable tabs. Suggestions appear below the focused input, with literal DSL tokens and localized descriptions. Up and Down choose a suggestion, Return and Tab insert it, and Escape closes the list. Insertion replaces the token prefix at the caret and preserves the rest of the query. The searchable table remains below the filter, as in the Lazyweb Base44 and Vercel references.

The HTTP service domain cell opens a valid HTTP or HTTPS asset URL in the default browser when selected. The destination must have a host and no embedded credentials. Other service rows retain the plain domain cell. The Linux guest stays isolated, and the default browser owns the user-initiated navigation.

Asset rows participate in the native table selection. The visible selection is a projection of the same set used by checkboxes, so updating the current page preserves selections on other pages. The Delete command on the focused table opens the existing confirmation for that set. Lazyweb's Aboard and Confluence examples retain visible bulk actions and a separate confirmation step.
