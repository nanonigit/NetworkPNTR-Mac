# Controlled source blob interruption: proof regression prevention

## Reproduction and timeline

6f7e15e defines a missing DEBUG witness (compile RED); d0f4659 passes six witness/state tests. b124110 executes actual socketpair staging and reproduces three missing-observation assertions:4096 bytes were written privately but no owned diagnostic scope observed them. fb6a13c connects staging and injects monotonic clock observations; staging passes but two late-recorder assertions fail.3b465e8 stores/checks the deadline under the same lock and all eight pass.953b9ef adds the missing live-VM CLI contract before bb9658b integration.

Independent review caught a second race: a metadata await separated the initial nil-probe check from assignment. f3f4267 adds the atomic claim contract (compile RED). 4a9f3ee passes the19 related cases; the fix claims on MainActor with no suspension and rechecks actual VM liveness immediately before claim, preserving a previously installed diagnostic scope. Both findings affected DEBUG verification correctness; no default app profile was promoted or external target contacted.

## Five Whys

1. Why could a late cancellation look valid? The recorder accepted any still-paused state.
2. Why could state remain paused after expiry? The waiting reader had not yet resumed its deadline check.
3. Why was its check insufficient? Cancellation and timeout are concurrent state transitions.
4. Why could another diagnostic owner be overwritten? Vacancy was checked before an await.
5. Why centralize transitions? Time validity and ownership vacancy must be checked at the actual locked/actor-isolated transition, not before a suspension.

## Fishbone and repair

Timing: stored monotonic deadline checked under the condition lock by the recorder. Ownership: MainActor vacancy claim after metadata; conditional cleanup preserves replacement owners. Identity: raw ID bytes, side, length, hash and operation UUID; duplicates invalidate evidence. Transport: first successful append then bounded DEBUG reader pause; cancellation shuts down the actual open socket before recording. File/auth: require absent destination/stage, unchanged auth revision and uncanceled parent. Scope: explicit TaskLocal inside detached worker only, finding diagnostics separate, no release helper. Cleanup: await/drain child and discard any returned receipt on every failure.

## Recurrence prevention

Retain wrong-byte identity/side/hash/size, duplicate, pre-body, completed-socket, timeout, deterministic late-recorder, actual partial-staging and TaskLocal isolation tests. Retain live-VM preflight and scope claim regression. Actual guest interruption plus subsequent normal byte verification and reboot must pass before counting this gate. A controlled reader pause is explicitly recorded; it does not prove naturally timed cancellation or spontaneous network failures. UI/panel/browser21/kernel/provider/harness/release acceptance remain independent.
