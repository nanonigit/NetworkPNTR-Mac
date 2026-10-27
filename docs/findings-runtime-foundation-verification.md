# F4b runtime experiment foundation

Status: foundation verified; F4b runtime acceptance remains open. Tested implementation: `6a21e66`. The fixed browser remains `e75ae371ad777ffd1eecdd28d2781a6519b05591`.

## Scope and evidence

The finite transport admits only known Findings reads, PATCH9101 and DELETE9102/9133. It enforces128 requests,90 seconds, cancellation before/after dispatch,4MiB responses and64KiB write bodies. Supplied bearer tokens, foreign IDs/routes, ambiguous query keys and invalid fields never reach the underlying client. No retries are introduced. Seven transport tests cover these boundaries, including valid JSON over each body/field limit and pre-cancellation without a caller-side guard.

The independently described Swift fixture is checked against the checksum-bound33-row SQL seed. Its43 query vectors include flat20 pagination, both sorts, every4severity/9status/3class/12task choice, literal/NFC/escaped searches,5asset scopes and a combined filter. Three fixture tests include fixed golden page/group orders and the expected final31-row mutation projection. These are expected values, not proof that a backend returned them.

The response verifier checks ordered IDs/counts/page metadata, exact UTF8 name/class/summary/evidence/report/task description, owned provenance, ordered asset ID/type/label tuples, timestamps and seeded zero counters/non-stale state. List reports must be empty; detail reports must match the seeded report. Four tests exercise all33 details,43 pages and corrupted fields, including canonically equivalent but byte-different Unicode. Do not use Swift String equality to claim raw-content preservation.

The single-use initial read stage dispatches43 lists and33 details through the finite gate. Three replay-transport tests establish76 unique requests, no successful report after malformed page/detail or cancellation, no error retry and no stage replay. They exercise orchestration only; no ARTEX API or VM was contacted by these tests.

The generated asset sentinel `__none__` / kind `none` now uses the native en/ja catalog for visible and expansion accessibility text. Raw labels and user content stay intact. The offscreen regression covers both locales and custom Unicode labels. Findings has62 owned catalog keys. Actual visible/AX comparison still waits for manual unlock.

## Regression investigation

MUSUBI sequence: reproduce missing APIs as compile RED; inspect pinned DTO/SQL and fixture values; isolate the test codec collision and unchecked fields; repair; verify independent positive/negative cases. Missing-verifier RED `c1429aa` -> minimal GREEN `83a3116`; field-drift RED `d849eea` -> GREEN `ca987fa`; read-stage RED `b699a9e` -> GREEN `6a21e66`. Existing sentinel RED `0de120c` -> GREEN `2332c24`. Read-only review found no remaining blocker in this finite scope.

Five Whys: positives first failed decoding because the test emitted both numeric `task_id` and string `taskId`; snake-case decoding collapses those aliases; the helper retained seed-only keys while adding wire keys; fixture conversion lacked one authoritative wire key; prevention is explicit removal/conversion plus complete positive decoding before negative assertions. Fishbone: data (seed/wire distinction), codec (snake-case aliases), assertions (asset ID sets), process (source review). Timeline: compile RED, codec failure, unique-key correction, deliberate field-corruption RED, complete verification GREEN, full regression. The asset assertion gap affected the test verifier, not product mutation behavior.

## Remaining acceptance

Aggregates/groups/asset tree/per-task/inherited and legacy context checks, mutation/unknown acknowledgement orchestration, DEBUG guest audit/seed/probe and independent reference runner are still required. Then perform actual fresh seed, hydrated mutation boot and same-disk persistence boot in the VM and matching pinned reference, comparing canonical reports. Preserve failure state, partial-PATCH observations, full stopped logs and cooperative-stop evidence. No VM/reference mutation was run in this checkpoint. F5 advanced Findings, all21 workflow gates, cloud egress, intermittent-kernel investigation, clean-Mac and release remain open.

Validation: full596Swift cases (595pass,1existing explicit AX skip),95Python pass, signed build-only/strict signature, packaged62 keys per locale, baseline inventory unchanged. The first Python run had94pass/1environment error because Node was absent from PATH; specifying its existing Homebrew directory resolved it without code changes. LLVM line coverage: fixture94.70%, transport97.73%, verifier100%, read stage100%. See evidence/findings/f4b-foundation-verification.json. There are no Python/Node dependency manifests to audit for this standard-library fixture change.

CI counter-evidence: run40466516578/head184adac failed to compile two inferred test-data expressions. A shared explicitly typed helper preserves assertions and wire values; full local596 cases still give595pass/1AXskip. This test-only compatibility repair requires its own exact-head CI confirmation. See bugs/findings-runtime-ci-typecheck.md.
