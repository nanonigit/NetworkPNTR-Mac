# Captured runtime investigation

## Reproduce and collect
Native init used an empty proxy flag, leaving traffic APIs unavailable. Fixed-source inspection showed traffic.Open is conditional on a proxy address. The independent real-loopback scenario exposed an additional slow-header shutdown hang: a partial HTTP header blocked the serial handler before the timeout formerly set inside exchange(). A bounded child timed out at7seconds (RED); moving timeout to the handler class applied it during socket setup and shutdown completed at approximately3seconds (GREEN).

## Root cause
5 Whys: no capture candidates because the index was unopened; unopened because proxy was empty; empty because isolated bootstrap disabled the listener; disabled because offline isolation was conflated with loopback recording; missing acceptance because seeded snapshots and picker unit tests did not exercise an actual recorder. The slow-header branch failed because the deadline began after header parsing, leaving the parser outside its intended bound.

Fishbone: configuration—empty proxy; transport—parser before deadline; oracle—source/filter checks initially too permissive; provenance—mutable on-disk inputs and post-removal parent checks; acceptance—reference process restarts differ from native VM boots and UI interaction.

Timeline: capture fixture RED56e526e → GREEN414db0d; partial-header REDbfff49e → GREENc2c4d9b; reference REDc981fd6 → GREEN28c4740; host RED23de817 → GREEN67a473c; receipt negatives9ce499e → strict rows/source11be4dd; immutable input/parent guard RED929e82f → GREENde795ec. Initial reference success was retained separately; hardened repeat verified the same normalized exercise with source hashes and pre-removal safeguards.

## Repair and verify
Guest-only127.0.0.1:8788 listener, guarded fixed29-exchange generator, parser-inclusive3second timeout, exact filter/source assertions, frozen source bytes verified in guest, and original-tag checks before owned alias deletion. New16 and full171 Python tests passed; isolated real runtime passed repeatedly. See captured-runtime-verification.md for narrow coverage and persistence scope.

## Recurrence prevention
Retain negative tests for wrong source, filter rows, partial headers, changed source files and missing parent tags. Refuse existing index, non-owned guest/network/DB, and unsafe cleanup. Never infer native artifact delivery from bootstrap source edits, or native UI acceptance from a reference container. VM rebuild/two-boot comparison and visual/accessibility gates remain open. No cloud or third-party targets were contacted.
