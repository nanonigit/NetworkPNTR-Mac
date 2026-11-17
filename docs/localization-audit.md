# English and Japanese localization gate

User requirement: final application supports en and ja only. Status: initial audit, not implementation acceptance. Browser reference remains e75ae371ad777ffd1eecdd28d2781a6519b05591.

| Finding | Evidence | Required treatment |
|---|---|---|
| Native strings mostly hardcoded Japanese, sidebar feature names English | Sources/NetworkPNTRMac; actual A6/A7 screenshots | Localize app-owned strings via catalog; verify both locales, including accessibility |
| Chinese default Auto description | Fixed browser db/db.go:212; both A6/A7 native/browser AX | Translate known builtin default display; preserve edited/custom descriptions |
| Korean default conversation title | Fixed browser server/conversations.go:56; A7 native/browser AX | Localized default presentation/new creation; preserve custom names and existing raw data |
| Chinese generated terminal summaries and Korean error prefix | A6 actual persisted-body screenshots/AX | Audit backend-generated system templates and generation-language directive separately from historical model/user content |
| Backend output language supports five values and defaults can fall back to Korean | Fixed server/errmsg_i18n.go, errmsg_catalog.go, server.go:3405/3536 | Native switch offers en/ja only and synchronizes authenticated output_language; test stored unsupported locales |
| Guest startup currently fixes ARTEX_LANG=ja | guest/backend-init:75 | Carry validated supported preference; persistence and restart test |
| Korean/Chinese exact-match diagnostic strings remain in ChatService | Static no-provider allowlist, emits Japanese instruction | Internal matching data is not untranslated UI; output instruction must follow selected locale |

| Chinese automatic task/asset provenance summary | Fixed db/schema.sql:667-683, sync_task_asset_links; F4a fixture creates33 system links | Localize the known system default when presenting provenance; preserve raw reference rows and custom summaries. Actual displayed acceptance pending |

Acceptance: both locales across all21 features and every migrated state; first run, bidirectional switch, restart and existing data; accessible names/help, dialogs/menus/errors, builtin agent labels, empty/loading views and new system messages. Missing resources use English fallback. Inspect rendered AX/screenshots, not source scans alone. No Hangul in product-owned displayed strings; identify Chinese by known phrase/catalog provenance rather than banning Han characters. Explicitly exclude user/custom/imported content, prior transcripts and model quotations from destructive translation. Confirm user-directed output-language requests remain possible.

Historical initial snapshot: no language switch/catalog/backend synchronization yet; entire language gate remains open. Preserve current UI failure evidence and fixed browser; do not silently pull a translated baseline.


F3.2 progress: the native app now has an en/ja switch and shared catalogs; Findings adds61 packaged owned keys. This does not close the full21/backend-output/actual-UI gate. F4a source audit found the trigger-owned Chinese literal `任务执行期间自动关联` for source=system. It is a known generated default, not user content. Keep the frozen reference and fixture unchanged; add localized native presentation when task/asset provenance is migrated and verify en/ja plus edited/custom text retention. No displayed UI acceptance is inferred from SQL/source evidence.

F4b source audit found the generated asset-tree sentinel `__none__` / kind `none` with label `未关联资产` (fixed db/finding_assets.go:185). Native visible text and expansion accessibility text now use an owned en/ja catalog key for that identity only: “Unassigned assets” / “未関連の資産”. The raw node, custom labels and frozen browser remain unchanged. The focused offscreen regression passes; rendered visual/AX acceptance remains pending. Findings now contains62 owned keys.

## Agent Skill descriptions

Localize the two descriptions exposed by the pinned catalog for
`api-recon` and `playwright-cli` in the Agent Skill tab. Retain the
identifiers, stored metadata and authored text. Glean's agent-library
reference informed keeping the skill key distinct from explanatory text.
Match the skill identity and exact UTF-8 default description before using
the English or Japanese string. Test both locales, customized metadata,
and the actual native controls. Editable agent prompt text has a separate
migration requirement.

The disposable pinned API returned three skill identifiers. Only the two
above had descriptions. The Swift regression run passed 1,088 tests with
one existing accessibility skip. The signed Release preview includes both
language resources and uses the current cloud7 guest. The diagnostic VM
reached authentication and restarted, then exited after the external review
window expired. The native skill row and browser GUI comparison still need
an interactive check.

The Worker prompt visible in the earlier native test is stored editable
content. Its fresh seed and reset path both derive from the pinned in-code
default. A migration needs to cover those paths and distinguish existing
user revisions. Separately, the guest boot environment defaults to Japanese,
while the Mac language picker changes app preferences and the view locale.
The pinned backend already has a persisted `output_language` field on
`/api/settings`, which can be exercised independently from prompt translation.
