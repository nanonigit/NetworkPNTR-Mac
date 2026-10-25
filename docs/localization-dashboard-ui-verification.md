# Dashboard UI localization — L7

## Reproduce and collect

After L4c migrated error identities, the four Dashboard view files still used Japanese headings/help, with raw task/engine/severity labels. Source inspection establishes the remaining localization gap; no new native UI reproduction is claimed. The matrix defines103entries:88UI/activity labels/templates and15status labels projected from pinned browser status.task/status.engine/status.severity. The independent status fixture records baseline `e75ae371ad777ffd1eecdd28d2781a6519b05591` and source JSON hashes; source HEAD was rechecked.

`9a2e383` is intended compile-time RED for missing DashboardLabelDomain/DashboardLabels and keys. `a41c2fa` passes the same3tests. Tests check the complete en/ja matrix and placeholder parity, every pinned status, exact unknown/custom preservation, tool-name precedence, metrics before/after display across both token sources, and opaque task descriptions containing template-looking text.

## Analyze

5 Whys: Dashboard stays mixed/raw → view strings and status values bypass catalog → initial charts/metrics port preceded app localization → status identifiers and display labels were coupled → no display-only boundary covered all panels. Fishbone: source/ledger definitions, status provenance, opaque content, chart series/scale keys, selectors/day IDs, formatter arguments, stale timestamp locale, immutable metrics/query paths. Timeline: source/pinned-status/Lazyweb → requirements/design/tasks → intended RED → catalog/helper/views GREEN → review/full tests/coverage → signed resources. Lazyweb `usage analytics dashboard` returned strong Google Analytics metadata(.631), but its image was not inspected; metadata is not rendered parity evidence.

## Repair

Headings, summaries, selectors, empty/loading/stale states, period labels, chart axes/series/legend/accessibility, activity/task/finding/asset/traffic/system panels resolve the current en/ja locale. Both chart marks and legend scale use the same localized series keys, retaining blue/green/purple. The standalone last-loaded timestamp explicitly uses the selected locale; its stored time is unchanged. Named templates use the existing single-pass formatter.

DashboardLabels maps only known exact task/engine/severity identifiers to the pinned translations. Unknown values remain literal, without trimming/case-folding. Five known activity kinds now have native display translations; this is an intentional localization difference from the browser's raw activity identifiers. A supplied tool name still takes precedence for tool_use. Worker names, custom descriptions, model/profile names, asset type names, summaries, URLs, and unknown values remain untouched. Colors/filters continue to use raw identifiers.

Core DashboardMetrics/Models/Service/Store are byte-for-byte unchanged from the pre-migration tree. Picker tags and chart scale color order match; four view files have zero CJK source lines. These are source invariants, not proof that runtime content cannot contain CJK or that chart state survives rendering. No locale-based view identity/task, polling/query/navigation change, or data migration is introduced.

## Verify and preserve remaining gates

264Swift cases:263pass, one existing AXskip;52Python pass. Display helper line coverage100%. Read-only reviewer approved translations, unknown/tool preservation, matching chart scale keys/colors, selectors and navigation. Final signed application build/strict signature/exporter checks pass; all103entries in each bundled language match the matrix and16template placeholder sets match between locales. Evidence: `evidence/localization/dashboard-ui-*`.

Actual chart legend/colors, selected/hovered day, profile/source/period/disclosure/scroll preservation, stale/retry/empty screens, navigation and VoiceOver/IME must still be compared in native/browser after the user unlocks the Mac. No new runtime fixture, screenshot, cloud call or UI attempt was made. Runtime/backend language/default-title provenance, remaining18screens and full21feature/runtime/distribution acceptance remain incomplete. The full goal stays active.
