# F3 Findings screen

The final target remains every pinned browser Findings workflow. F3.1 implements the window-owned screen coordinator before F3.2 adds native controls. No screen, VM, browser, keyboard or accessibility acceptance follows from coordinator tests.

## Requirements and design

- Keep one FindingStore per authenticated window; locale/sidebar changes retain filters, selection and drafts. Stop invalidates read/dialog ownership; logout resets private transient state. Neither releases a dispatched mutation gate early.
- Capture record, view owner, session owner and uncertainty revision when opening a confirmation. Submit only that context once. Confirmed results close the dialog; post-handoff failures remain unconfirmed and cannot be replayed. Explicit acknowledgement refers to the captured uncertainty episode, never a newly read revision.
- Persist only browser-equivalent view, severity, status, vulnerability class, task and sort preferences in bounded versioned JSON. Do not persist search, pagination, asset scope, selections, report bodies or drafts. Unsupported/corrupt preferences fall back safely without making network requests. Preserve literal Unicode bytes in user values.
- F3.2 will use native list/detail and asset navigation, explicit filters and independent server cursors, six counters and contextual read-only provenance. Capture preferences and confirmation logic here so controls cannot substitute a newer owner at click time. Read scheduling must preserve an in-flight same-query asset tree across scope/page changes.

## Design evidence

Pinned source: e75ae371ad777ffd1eecdd28d2781a6519b05591, findings/page.tsx and findings-table.tsx. Lazyweb desktop search `vulnerability findings table filters` returned adjacent table/filter metadata (top similarity 0.442); no external screenshot was inspected. Use it only as metadata, not visual evidence. The fetched [data-table-filters practice](https://raw.githubusercontent.com/openstatusHQ/data-table-filters/main/skills/data-table-filters/SKILL.md) supports explicit filters, stable row identity, a detail panel and capabilities off until implemented. No React dependencies or upstream installation commands apply to SwiftUI. The macOS SwiftUI Patterns split/inspector guidance supports explicit selection and native system surfaces.

## Ordered verification

F3.1: execute missing-coordinator RED; implement bounded preference round-trip, captured edit/delete/acknowledgement and stop/reset ownership; run controlled stale-dialog, held-write, uncertain replay and Unicode tests; review, regression, signed build and exact-head CI. F3.2 native controls/presentation/localization and offscreen hosting follow. Actual en/ja browser/native screenshots, keyboard and VoiceOver wait for manual Mac unlock. F4 actual disposable VM/reference mutations and F5 export/traffic/report/lineage/retest/deepen remain required.


F3.2 implements the three-view native workspace with a list/detail split, explicit filters, independent pagers, raw-byte iterative asset rows and captured confirmation bindings. RootView retains the window model per authentication identity. Gate-aware coalesced reads survive scope/page updates during an active tree snapshot, while query invalidation follows F2. Separate stats polling remains independent. Lazyweb issue-list metadata search9599af57-1296-4997-8ef8-aca8713d1a4a returned aboard/linear adjacent references (top0.511); no external screenshot was inspected. Tests must cover stale bindings, raw-Unicode trees, maximum counters/cursors, held read handoffs, model reset and offscreen en/ja hosting. No actual visual/keyboard/AX acceptance while manual unlock is deferred.
