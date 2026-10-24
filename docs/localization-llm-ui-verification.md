# LLM settings UI localization — L6

## Reproduce and collect

After L4c localized native errors/notices, five LLM view files still contained fixed Japanese controls/help: settings/cards, profile editor/model picker, rotation, global retry, and numeric/retry form fields. Source inspection established the remaining gap; this checkpoint does not claim a new native UI reproduction. The reviewed matrix in `Tests/ArtexCoreTests/Fixtures/llm-ui-localization.json` defines108typed en/ja entries, including11parameterized templates.

`e377f16` is intended compile-time RED for missing AppStrings.formatted/render. The initial test setup used a nonexistent retry-policy initializer and was corrected to the existing mutable property API before the authoritative RED; that mistake is not a product failure. `c855245` passes the same3tests. Tests verify every catalog entry against the matrix, repeated/missing/unterminated tokens, opaque mixed-language model names containing template-looking text, and unchanged draft/retry encoding after display operations.

## Analyze

5 Whys: LLM UI stays Japanese → labels/help are literals → initial feature migration predates the global language requirement → model values and presentation were not consistently separated → shared typed presentation was added only in later localization phases. Fishbone: key ownership, dynamic values, protocol tags, partial numeric input, retry dirty state, fieldGeneration, sheet/task identity, placeholder recursion, resource packaging. Timeline: source/Lazyweb → requirements/design/tasks → corrected test setup/intended RED → keys/single-pass formatter/view wiring → GREEN → reviewer/full regression/coverage → signed resources. Lazyweb `AI model provider settings` returned moderate V7 metadata(.535); no image was inspected or used as parity proof. The pinned browser remains authoritative for workflow comparison.

## Repair

All fixed native LLM controls, labels, help, empty states, confirmations, and numeric validation now resolve the current locale. Dynamic templates substitute tokens only from the original catalog text, never recursively from model names or masked hints. API/protocol raw tags, profile names/model IDs, masked key hints, model replies, and existing backend pool diagnostics stay literal. The latter may still contain other languages and require the separate provenance/backend gate.

No service/model/credential changes, locale-based view identity/task, or new mutation is introduced. The five files have zero CJK source lines after migration, and before/after Picker tag expressions match. This is a source audit, not a runtime language audit. Bindings, numeric parsing/validators/partial text State, retry dirty flags, action closures, and existing fieldGeneration changes on confirmed save/reload remain unchanged. Locale-specific layout/field identity still requires actual testing.

## Verify and preserve remaining gates

261Swift cases:260pass, one existing AXskip;52Python pass. The formatting helper has100% measured line coverage. Read-only review found no concrete formatting/translation/state/wire defect. Final signed app build/strict signature and exporter checks pass; all108LLM UI strings per language match the reviewed matrix in the signed bundle. Source scan/coverage/result artifacts are under `evidence/localization/llm-ui-*`.

The user deferred Mac unlock; no new runtime fixture, UI attempt, screenshot, or cloud request was made here. Actual en/ja layout, dropdowns/sheets, invalid numeric-text preservation, unsaved retry fields, connection-test/model selection, VoiceOver/IME and fixed native/browser comparison remain open. Dashboard/runtime labels, backend language/default-title provenance, remaining18screens and full21feature/runtime/distribution acceptance remain incomplete. The full goal is active.

CI correction: hosted40135493632 at31d8fad failed exactly two raw-Data equality assertions in the wire-preservation test. BackendJSONCoding uses JSONEncoder without sorted keys; object byte order is not the wire-value invariant. Compare parsed, sorted-key JSON instead, with reordered-equality and changed-value-inequality controls; production encoding stays unchanged. Equal byte lengths alone did not prove value equality; successful canonical comparison on the hosted rerun is required. d09e852 was mistakenly committed with GREEN wording while its test still failed to compile (missing second-argument try); it is an invalid checkpoint, never passing evidence.1da4b81 fixes that syntax, then the focused3tests actually pass. The reviewer approved semantic comparison and controls. Preserve the failed run/mislabeled checkpoint as counterevidence; do not report remote success until final CI passes.
