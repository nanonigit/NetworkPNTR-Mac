# T11 catalog receipt validation investigation

Collect/reproduce: same-ID clear-template PATCH receipt with wrong name passed the native exercise if the following GET was correct, while the Python reference rejected it immediately. Controlled runtimeREDed12533 ran18calls instead of stopping at8 and produced2failed assertions. No VM was started for the reproduction.

Five Whys: cleared receipt ignored -> only owner checked by generic service -> exercise relied on later readback -> native/reference asserted different stages -> initial malformed-only negative matrix missed valid contradictory receipts. Fishbone: contract(receipt vs eventual state), data(valid fields with wrong content), test(valid negative vs malformed), implementation(discarded return), comparison(asymmetric checkpoints).

Repair: capture clearedReceipt and compare all five fields with TaskTemplateDraft.sameBytes before GET, preserving explicit null/empty rules and byte spelling. Extend valid nonempty freshness, NFD/NFC readback, still-linked FK row and terminal-success/boot/stage/incomplete-report negatives. Timeline b0bf5b8missingRED ->0f164d3GREEN4 ->ed12533runtimeRED ->f770278GREEN6 ->full411/62 ->one actual VM15.33sec and reference12checks exactmatch.

Verify/prevent: keep valid contradictory receipt fixture in normal discovery; do not treat later GET as validation of an unchecked response. Actual reference and VM compare fixed normalized report, source image/binary hashes, auth/isolation/cleanup proofs. No retries after failure, no user state, no task/agent creation. Live-task movement, UI and restart reliability remain separate gates.
