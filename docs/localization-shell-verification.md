# Native language switching (L2)

## Evidence and acceptance scope

Requirements/design/tasks preceded catalog and UI work.2de5dfa RED requires a missing catalog API;f779cea GREEN4 tests adds compiled catalog/typed helper.5a66610 connects one State-owned preference to RootView's toolbar Picker without locale-based view IDs. d949dc8 RED6 assertions and ad9a7fe GREEN5 tests align six actual browser Japanese feature names after screenshot comparison.

Live signed5a66610 native V1 shows exactly English/日本語 options. ja->en->ja retains the same active Chat/conversation presentation, exact literal draft `L2 draft **literal**` plus newline and `日本語 中文 한국어`, and locale-l2.txt23B card. Ready remains visible; exact VZ-object identity was not separately instrumented. A new native process V2 retains selected English; original Japanese restored. Both processes exit0, VM stopped and temporary Keychain removed. Browser disposable settings switches en->ja->en and keeps five source options; native intentionally limits choices to two. All21 IDs have typed localized shell titles; feature implementation status remains independent.

Final234Swift cases(233pass/oneexistingAXskip),49Python pass. Core helper100% line/97.4% region coverage. Fresh scratch compilation initially exercises3catalog cases; later complete5case suite and full suite pass. Final signed ad9a7fe bundle contains only en/ja compiled resources and all six corrected Japanese names (shell-packaged-resources.json). Screenshots remain5a66610, before those Japanese copy changes; English screenshot and state-preservation code are unchanged. No latest-Japanese screenshot equivalence claimed.

## Resource lookup counterevidence

The first incremental catalog test had93 assertions fail, returning keys. Compiled top-level bundle contained en/ja strings. A temporary path probe subsequently showed the nested test resource bundle and passed without functional lookup changes; clean scratch build passed. The exact initial failure cause is unproven. Do not label it a confirmed Foundation or product defect, and do not infer full reliability from a warm cache. Cold CI and final signed resource/runtime checks are distinct evidence.

## MUSUBI investigation and prevention

Reproduce: missing API RED and actual six terminology mismatches. Gather: compiled catalog, cold scratch, native/browser AX/screenshots. Analyze: 5 Whys for terminology drift -> independent translation -> semantic similarity assumed sufficient -> pinned browser terminology not asserted -> use actual reference names in tests. Fishbone: source/compiled resource packaging, locale ownership, view identity, content provenance, vocabulary and cold/incremental builds. Timeline: research/source -> requirements/design/tasks -> RED/GREEN -> cold probe -> UI integration/review -> signed live switching -> terminology RED/GREEN -> final full tests/package verification. Prevent: typed fixed keys/all21 mapping, missing-ja English fallback, hostile variable text preserved, exact reference-name tests, no .id(language), external input/card checks.

Lazyweb search https://www.lazyweb.com/agentic-search/76693227-6d1e-45bf-9de0-c269b458b639 supplied selection metadata, not inspected screenshot proof. Fixed browser settings source124/665 and actual settings UI remain authoritative. No report generated.

## Remaining gates

Feature interiors still have Japanese hardcoded controls; builtin Chinese description/Korean default title remain observed. User-entered mixed-language draft is intentionally preserved. Native backend output_language sync is not implemented, while browser performs it separately. Raw runtime state labels, system menus, VoiceOver and full all21 states remain open. Retained private V1 disk holds guest fixture upload; individual guest-file cleanup/hash was not measured here. Reference containers/networks and selected host tmpfile were removed. No live cloud request; source-kernel reliability and complete app delivery remain unproven.


CI portability repair:40110609236 is a real hosted failure: native SwiftPM copied raw xcstrings, so resource keys were returned. This is separate from the unexplained initial local incremental failure. e3b4874 exporter RED3 ->3025b1b GREEN3exporter/52fullPython and5cold native-builder catalog tests. The authoritative catalog now produces committed UTF8 plist resources; raw catalog is excluded, both build systems process en/ja .lproj, and --check gates CI/app build. Stdlib trace measures94.6% exporter line coverage. Full234Swift pass scope unchanged(233pass/oneAXskip); final signed3025b1b resources checked. Live screenshots stay5a66610; resources are semantically equivalent except the six already documented term alignments. Hosted retry must pass before reporting CI success.
