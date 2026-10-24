# Chat localization checkpoint (L3)

The final product supports English and Japanese only. This checkpoint localizes migrated Chat controls, empty/loading states, attachment controls, and exact known builtin agent defaults. It does not complete Chat or the full localization gate.

## Implementation and regression evidence

- RED/GREEN commits: `0361718` → `cbd85b2` (catalog/default provenance), `6f99cf0` → `2a62b55` (native controls), `d90309a` → `5232876` (complete pinned builtin descriptions). The last RED produced six assertion failures; final text matches the fixed browser translations, rather than shortened descriptions.
- Final full run: 240 Swift cases, 239 passed and one existing AX test explicitly skipped; 52 Python tests passed. Signed application build and strict code-signature verification passed. Catalog export consistency and `git diff --check` passed.
- Core helper line coverage: AppStrings 52/52, BuiltinAgentText 15/15. Region coverage: 37/38 and 11/11 respectively. This is not aggregate UI, IME, or VoiceOver coverage.
- Existing NSButton/NSTextView instances update localized labels without replacing controls. Unit tests preserve editor text and selection and verify file-selection policy and upload counters.
- Builtin translation requires both the known agent key and byte-exact original default. Custom descriptions, edited defaults, unknown agents, conversation history, model output, mention tokens, and user text remain unchanged. No database rewriting is performed.

## Actual browser comparison

Baseline: `e75ae371ad777ffd1eecdd28d2781a6519b05591`. A disposable reference ran at loopback8789; the existing user service8787 was preserved. The signed native diagnostic application ran a dedicated VM with no NIC and no LLM profile.

Both applications retained the same literal multiline draft (`L3 **literal**` followed by Japanese, Chinese, and Korean user text) and a 21-byte attachment card across English → Japanese. The native file panel displayed English prompt/message. Browser locale was changed from a separate owned settings tab; its storage event updated the same Chat tab without navigation. Native language ended at the original Japanese setting. External caret position, actual IME composition, and VoiceOver were not measured; editor selection preservation has direct AppKit unit coverage only.

Screenshots/AX snapshots under `evidence/localization/chat-*` were captured at `2a62b55`. They predate the complete builtin wording correction in `5232876`; final six builtin strings were separately verified against the fixture and the final signed bundle. Do not describe those screenshots as proof of final builtin copy rendering.

Both fixture processes exited0. Native VM stopped and temporary Keychain entry was removed; the entire owned native State directory was discarded. Reference containers/networks and selected host temporary file were removed. This run does not claim an individual guest-file hash or authenticated deletion check. See `chat-fixture-cleanup.json` and `chat-native-results.json`.

## Chinese/Korean audit and remaining gates

The Chinese builtin Auto/Pentest defaults have English/Japanese presentation translations with exact provenance tests. The Korean initial conversation title is still unresolved: the fixed backend recognizes its original sentinel for automatic first-message naming. Sending an explicit localized title would disable that behavior. An uncommitted proposal was withdrawn before implementation; its missing-argument probe is not a valid product RED. A provenance-aware backend change with auto-naming regression tests is required. Existing/custom conversation titles must stay intact.

Remaining: backend output_language synchronization and recovery, errors/Auth/Runtime/LLM/Dashboard interiors, system menus/raw lifecycle labels, default-title provenance, actual IME/VoiceOver, full English/Japanese audit of all21 features, cloud/runtime acceptance and distribution. Eighteen other feature screens remain unimplemented. No whole-language, Chat, or application acceptance is claimed.
