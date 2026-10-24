# Authentication and terms localization — L5

## Reproduce and collect

Authentication controls and the terms sheet used fixed Japanese labels; the sheet always called the Japanese-default terms loader. Source inspection identified both gaps. No new native UI reproduction was attempted while the user deferred Mac unlock.

`b4c3172` is intended compile-time RED for the missing typed keys/combined document loader; `3c70904` passes the same3tests. There are23auth catalog entries. Complete28-entry documents for both languages match the checked-in fixture projected from `auth.terms` of pinned browser `e75ae371ad777ffd1eecdd28d2781a6519b05591`. The fixed source HEAD was rechecked. The fixture records source file SHA256 values. Legal text/resources were not rewritten.

## Analyze

5 Whys: terms remain Japanese → loader uses its default → sheet loads a single rendered language → document selection is not derived from view locale → initial authentication port preceded global localization. Fishbone: label ownership, document source/version, state/field identity, scroll callback timing, empty/failed load, catalog packaging. Timeline: source and Lazyweb research → requirements/design/tasks → intended RED/GREEN → reviewer/source discovers existing empty-scroll latch → separate reading-state RED/GREEN → full tests/coverage/review → signed resources. Lazyweb `terms agreement modal` returned moderate adjacent Postman EULA metadata(.479); its image was not inspected and is not parity evidence.

## Repair

Auth controls use typed en/ja catalog strings. Native-specific copy still describes fixed username ARTEX and automatic setup-token handoff accurately. Both supported bundled documents load once into the existing sheet; its current locale selects content. No language-based view identity, locale task, network fetch or password/key persistence is introduced. Existing fields/focus/phase-clear/submit/logout/checkbox semantics are unchanged. Follow the pinned browser's per-open read latch across locale changes; do not invent an additional per-language agreement gate.

The adjacent existing native read gate could latch from empty geometry before async terms loading. `cc1e53c` requires reading state in a separate compile-time RED; `a9e3fa3` passes all5focused tests. AuthTermsViewport equality includes document availability and atEnd, so availability can change the observation even for a short document that stays atEnd=true. AuthTermsReadingProgress ignores unloaded geometry and requires loaded content for Agree. A valid loaded end latches within the open sheet, including a later locale change. Fresh state is unread; failed/empty documents cannot enable the button. This is a functional reading UI fix; the independently existing agreement checkbox remains unchanged.

## Verify and preserve remaining gates

258Swift cases:257pass, one existing AXskip;52Python pass. Loader and reading helper each have100% measured line coverage. Read-only review approved locale/state wiring and reading-state transitions. Final signed build, strict signature and exporter drift checks pass; bundled23auth strings per language and both28-entry terms documents match authoritative sources.

The tests establish resource/state behavior, not SwiftUI geometry delivery or native control preservation. Actual empty→loaded scroll callbacks, short-document callbacks, read-to-end/close/reopen, language switching with passwords/focus/checkbox/sheet/scroll position, IME/VoiceOver, and fixed native/browser comparison remain pending after unlock. No new runtime fixture or screenshot was created here. All21feature/full localization/runtime/distribution acceptance remains open, including other screen labels, backend language/default-title provenance and remaining18screens.
