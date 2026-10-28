# Evidence runtime diagnostics: ownership and verdict regressions

## 1. Reproduction

Initial fixture tests passed8 cases, then11 with preparation/database/activity proof checks. Review added a replaced-created-file cleanup case, failed-unlink case and a FIFO opened without a writer. cf31f29 reproduced3 failures in14 cases: a replacement was eligible for deletion, cleanup failure was hidden, and FIFO audit blocked until the bounded child test killed it.

Native diagnostics separately needed a truthful final-write/cleanup contract. dd82b15 added missing/inaccessible report contract tests before the correction. These were compile-time RED contracts, not claims of an executed final-write behavioral failure. be693f7 passed9 helper/client/report cases. A first actual signed two-boot run exited0, saved all4 bodies twice and rejected logout/stop/restart receipts; it did not witness live cancellation.

Partial-file observation alone could still mistake a completed worker awaiting MainActor acceptance for an interrupted stream. c05edb0 added the missing operation-witness contract, including an actually closed socket whose later cancellation must not count. 9b41048 passed12 related cases and supplied the exact request/operation cancellation result. A fresh signed two-boot run then exited0 with witnessed caller cancellation and live VM stop.

## 2. Evidence

Cleanup recorded only names and ignored unlink failures. An O_RDONLY FIFO open blocked before descriptor validation. The initial probe set success before a potentially throwing final write and did not inspect staging directories on failure. The first proposed live-cancel observation measured earlier partial bytes but not whether cancellation reached an open descriptor. None of these developer diagnostics was accepted as completed product behavior.

## 3. Cause analysis

5 Whys: cleanup could delete a replacement because it identified ownership by pathname; incomplete cleanup looked successful because unlink exceptions were swallowed; the original model treated attempted cleanup as completed cleanup; adversarial namespace/type fixtures were missing; developer-only code had been held to a weaker ownership model. Root cause: missing inode/type and explicit cleanup-result contracts.

For verdicts: a failed final write could leave an in-memory passing result because success was set before persistence and never cleared; cleanup status relied on attempted disposal/shutdown rather than observed residue. Root cause: computation, persistence and observed process outcome were conflated.

For live cancellation: partial bytes and an unsettled MainActor task were only an earlier observation; the detached worker could finish before cancellation. Root cause: no operation-specific interruption acknowledgment.

Fishbone: filesystem identity/type; ignored cleanup failures; report I/O ordering; async worker-versus-acceptance timing; insufficient negative fixtures. Timeline: missing fixture RED21550ff -> GREENef1c42d/84ed150 -> ownership/FIFO REDcf31f29 -> GREENaec5b46 -> client RED5a7e774/GREENa4dc815 -> file/report contracts RED4813259/dd82b15 -> GREENbe693f7 -> partial witness RED886d500/GREENd8252f9 -> operation witness REDc05edb0/GREEN9b41048 -> actual live acceptance.

## 4. Repair

Retain created device/inode identities, preserve mismatched replacements, attempt all owned cleanup and report incomplete cleanup. Open audit descriptors with O_NONBLOCK/O_NOFOLLOW before regular-file validation. Gate report publication on exact boot/file/ownership facts, clear success on every failure, and inspect owned output/download directories for residue. Accept a run only with independently observed terminal exit0 alongside its report: filesystem failure may prevent rewriting an old snapshot.

The DEBUG/package-only cancellation witness captures the exact operation UUID and full manifest, and records the cancellation handler's atomic socket.cancel() result. Closed-worker, duplicate or foreign observations cannot pass. The VM-stop path separately requires exactly1 interrupted registered transfer. All operations are drained before inspecting cleanup. Production release transport has no diagnostic hook.

## 5. Verification and recurrence prevention

Keep the14 Python cases and12 native observer/client/report cases, actual regular/empty/large files, bounded FIFO subprocess, injected final-write failure, residue/symlink checks and closed-worker cancellation negative. Native run1 is retained as evidence-export-native-initial.json; run2 is evidence-export-native.json. Both have terminal exit0. Run2 observed237320 bytes before caller cancellation and696832 bytes before VM stop, then repeated all4 complete downloads after restart. Neither run proves browser/API comparison, UI acceptance, default-kernel promotion or full release readiness. See evidence-export-runtime-verification.md for full regression/publication status.
