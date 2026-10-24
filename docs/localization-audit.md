# English and Japanese localization gate

User requirement: final application supports en and ja only. Status: initial audit, not implementation acceptance. Browser reference remains e75ae371ad777ffd1eecdd28d2781a6519b05591.

| Finding | Evidence | Required treatment |
|---|---|---|
| Native strings mostly hardcoded Japanese, sidebar feature names English | Sources/ArtexMac; actual A6/A7 screenshots | Localize app-owned strings via catalog; verify both locales, including accessibility |
| Chinese default Auto description | Fixed browser db/db.go:212; both A6/A7 native/browser AX | Translate known builtin default display; preserve edited/custom descriptions |
| Korean default conversation title | Fixed browser server/conversations.go:56; A7 native/browser AX | Localized default presentation/new creation; preserve custom names and existing raw data |
| Chinese generated terminal summaries and Korean error prefix | A6 actual persisted-body screenshots/AX | Audit backend-generated system templates and generation-language directive separately from historical model/user content |
| Backend output language supports five values and defaults can fall back to Korean | Fixed server/errmsg_i18n.go, errmsg_catalog.go, server.go:3405/3536 | Native switch offers en/ja only and synchronizes authenticated output_language; test stored unsupported locales |
| Guest startup currently fixes ARTEX_LANG=ja | guest/backend-init:75 | Carry validated supported preference; persistence and restart test |
| Korean/Chinese exact-match diagnostic strings remain in ChatService | Static no-provider allowlist, emits Japanese instruction | Internal matching data is not untranslated UI; output instruction must follow selected locale |

Acceptance: both locales across all21 features and every migrated state; first run, bidirectional switch, restart and existing data; accessible names/help, dialogs/menus/errors, builtin agent labels, empty/loading views and new system messages. Missing resources use English fallback. Inspect rendered AX/screenshots, not source scans alone. No Hangul in product-owned displayed strings; identify Chinese by known phrase/catalog provenance rather than banning Han characters. Explicitly exclude user/custom/imported content, prior transcripts and model quotations from destructive translation. Confirm user-directed output-language requests remain possible.

Known incomplete work: no language switch/catalog/backend synchronization yet; entire language gate remains open. Preserve current UI failure evidence and fixed browser; do not silently pull a translated baseline.
