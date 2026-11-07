# Guest boot investigation: native app checkpoint

Status: investigation in progress; no stable-runtime or product-completion claim.

## Evidence and timeline

1. P2 signed CLI boot/persistence/API tests passed, including normal and forced restart. This established functionality on successful boots, not long-run reliability.
2. A signed native .app fresh setup run using Alpine linux-virt 6.12.114-r0 failed in PostgreSQL startup with a guest kernel NULL dereference in fib_table_lookup. The host app recognized the kernel fault and stopped the VM. No credentials or browser state were used.
3. Another native run completed actual first setup and stored its session in Keychain, but encountered EAGAIN while restoring after restart. A separate socketpair regression reproduced a delayed response on a nonblocking descriptor. Poll the descriptor before reads/writes, retaining byte/time limits; this is an application transport defect with a verified targeted repair.
4. A pinned Alpine 6.18.58-r0 candidate with matching modules passed the CLI suite and one real native setup/login/Keychain-restore run. Another fresh run exposed a diagnostics race: it treated the existence of the auth-session object as completion of its asynchronous status request. Wait for a terminal auth-check phase instead.
5. A further 6.18 native run reproduced a guest undefined-instruction/paging fault during blank-disk scanning. A kernel-version upgrade alone is therefore not a demonstrated fix. A one-vCPU experiment timed out during the same scan; it was reverted. The new kernel was not promoted in the source recipe.
6. Compare a direct-root, built-in-driver kernel profile against the initramfs/module/switch-root profile. The already-installed official Docker Desktop GPL LinuxKit 6.12.76 kernel is a diagnostic input only, identified by SHA-256 35dc83e45a0cbf9a292469e902fd6a5f4db58c9ead47e69233b4197661795fc8. Its embedded configuration disables initramfs and includes block/ext4/vsock drivers, so it must boot the read-only system disk directly. This does not call Docker at application runtime. Do not distribute this binary without corresponding-source/license review or replace the portable source-build requirement.

7. Direct-root boot reached ARTEX readiness with no physical NIC, no active non-loopback interface and no external route. LinuxKit creates inactive fallback tunnel devices even without VZ NICs. Replace the overly narrow `lo`-only assertion with explicit hardware/up/route checks before backend startup and at readiness; unit fixtures reject each violation and missing evidence. Framework configuration still requires zero NICs and shares. This does not enable network access.
8. The first full direct-root run passed setup and normal restart, then the backend exited during forced-stop recovery. Its volatile private log was lost when the failed VM was stopped, so the application exit cause is unknown. Add bounded fixed-category log classification and numeric exit status; never print raw logs. The next full run passed all four boots, including forced restart and nonblank-disk rejection. One subsequent success does not erase the failure or establish reliability.

9. The first signed native app run on that same direct-root LinuxKit profile panicked during the blank-disk Python scan (`anon_vma_clone` / `__split_vma` / `munmap`), with no loadable modules. This contradicts the hypothesis that the initramfs/module/switch-root path alone explains the faults. The profile is not promoted. A one-vCPU direct-root comparison is diagnostic only; production remains two vCPUs pending evidence. No host or hardware cause has been established.

10. Direct-root LinuxKit with one vCPU completed three consecutive fresh signed-app diagnostics: nine boots total, actual setup/login, real Keychain restoration, logout cleanup, and cooperative stop during startup. These runs used a temporary one-vCPU build; no cause or release reliability claim follows. Add a bounded manifest CPU budget (1 or 2, default 2) so follow-up experiments are reproducible without editing source; unknown/out-of-budget values fail closed. Re-test the selected manifest through both native and CLI runners before accepting it. Portable kernel construction and visual/click acceptance remain open.

11. The fixed-category diagnostic reproduced `backend_exit_status=1` with `database_open,database_recovery` during a one-vCPU forced restart. This identifies a separate startup readiness race: process startup alone did not prove the actual application database accepted queries after crash recovery. Wait for an authenticated `SELECT 1` against that role/database, bounded and with credentials/logs private, before starting ARTEX. After the change the selected one-vCPU manifest passed the CLI suite with three consecutive forced recoveries (six boots including invalid-disk rejection), a further signed native setup/Keychain/login/startup-stop run, and the same five reference contracts. Committed normalized evidence is under evidence/native-auth. Kernel-fault root cause and release qualification remain unresolved.

## Causal analysis (5 Whys / fishbone)

Why did the first app run fail? The guest kernel faulted before backend readiness. Why could an earlier green result coexist? The failure is intermittent across otherwise identical boots; narrow success tests did not establish reliability. Why was an auth restore also failing? A nonblocking descriptor can report EAGAIN before data arrives; per-socket timeouts do not make it blocking. Why was a later completed boot marked failed? The diagnostic checked session allocation rather than the completion of its status request. Why is kernel root cause still open? Fault locations vary and changing the kernel version did not eliminate the symptom; boot profile, module loading, kernel configuration and host/framework behavior need isolated comparisons.

Fishbone axes: guest kernel/configuration, initramfs/module/switch-root lifecycle, block I/O and sparse blank-disk reads, vCPU scheduling, host/framework environment, and app-side readiness/transport timing. No fault is attributed to macOS, hardware, or a particular kernel patch without a controlled reproduction proving it. Related upstream reports are background only and have different signatures.

## Restoration criteria

- Repeat fresh native setup, real Keychain restore, wrong-password/terms rejection, logout, restart and stop-during-start on the final pinned profile; no Oops/panic/hang.
- Repeat CLI persistence/invalid-disk/reference-contract tests against that same profile.
- Preserve negative outcomes and explicit native-click/visual gates; a passing developer snapshot/service harness is insufficient for complete browser UI parity.
- Keep all state/secrets local and ignored. Publish only normalized non-secret results. Do not weaken host isolation or silently reformat existing disks to get a passing run.

## Portable source-kernel experiment (2026-10-23, in progress)

The Docker.app diagnostic kernel remains unchanged. A separate recipe pins upstream Linux 6.12.114, LinuxKit configuration commit f935f6b18cad69f08c1830b432d7dab90bf67614, an Alpine builder digest, an exact package inventory and explicit built-in driver overrides. Source unpacking/compilation occurs in a private Linux ARM64 container with network=none, zero host mounts, dropped capabilities and bounded resources. Download acquisition is separate from offline compilation. See kernel-build-design.md.

The first actual compilation failed while building the stackleak GCC plugin because gmp.h was absent. Why: runtime GMP was installed transitively, but compiler plugin headers require gmp-dev. Why was it missed: the previous dependency inventory covered normal kernel tools but not this preserved hardening plugin. Repair: add exact gmp-dev=6.3.0-r3 and lock the resulting 73-package inventory (including mpc1-dev=1.3.1-r1 and mpfr-dev=4.2.1_p1-r0 after the next compilation exposed mpc.h); do not disable stackleak. This build dependency error does not explain the earlier VM faults.

Read-only review found that incomplete exported artifacts and a mutable retained-source cache could undermine provenance. Require all seven output files, verify retained source/license against pinned digests and retain from the verified staged build input. Regression tests reject each missing output and source substitution. Explicit Buildx selection rejects remote/ambiguous builders. The reviewed Python suite has 24 passing tests; Swift core has 42 passing tests. At that tooling checkpoint, actual new-kernel boot and an independent reproducibility build were separate, pending gates.

The completed source-kernel candidate passed the six-attempt CLI recovery/invalid-disk suite and three fresh signed-app diagnostics, including setup/Keychain restoration, actual LLM/profile persistence and populated dashboard/reference comparisons. A second fresh offline compilation produces the same Image/config/build-report hashes. Retained license contents match; directory times in the archive and whole-builder manifest identities differ, so only kernel/config same-host byte reproducibility is accepted. See kernel-build-verification.md. The former two-vCPU fault cause remains unresolved and no release reliability claim follows.


## Source-candidate upload preflight run: new one-vCPU fault

Fresh signed native run upload-a2-v1 failed before bootstrap/readiness or any upload. The same source-built6.12.114-artex direct-root one-vCPU Image SHA2568e57308787c420cb42e4c4ea80e6def6438a52232692c010dc4609bb9bf21879 panicked in anon_vma_clone / __split_vma / munmap. The app detected the panic, force-stopped its VM and exited; its normalized result is diagnostics_failed, not upload success. Sanitized evidence is evidence/chat/upload-a2-boot-red.json; private raw logs/state stay ignored. This contradicts any inference that the one-vCPU source candidate is generally reliable. Earlier passing runs remain historical evidence only. No host/hardware cause is established. A second fresh same-profile attempt is a controlled reproduction, not a reason to discard this failure. Runtime promotion, reliable boot/recovery and release acceptance remain open.

## A4 handoff candidate: blank-check process fault

Fresh signed run attachment-handoff-a4-v1 failed before setup/bootstrap or any attachment operation. It reported stage=nonblank-state-disk, but the private serial log shows Bad rss-counter state for MM_FILEPAGES/MM_ANONPAGES, non-zero pgtables_bytes on freeing mm, then Segmentation fault in the Python blank checker. After app/VM termination, a host read-only full scan verifies the generated2GiB sparse fixture disk is entirely zero (allocated blocks0, SHA256a7c744c13cc101ed66c29f672f92455547889cc586ce6d44fe76ae824958ea51). Thus the stage label is not evidence of nonzero disk data; backend-init currently maps any blank-check process failure to the same fail-closed stage. No formatting occurred. Sanitized artifacts: attachment-handoff-boot-red.json and attachment-handoff-failed-native-results.json.

This is additional counter-evidence for the unchanged one-vCPU source candidate, with no established host/hardware/Python/kernel root cause. Do not bypass scanning or format the failed disk. One fresh same-profile control run is permitted to classify reproducibility and exercise the new feature; no repeated-until-green loop and no reliability acceptance follows from success. Keep the failed raw/state fixture ignored and untouched. A later startup-diagnostic repair should distinguish blank-check execution failure from legitimate nonblank exit without weakening rejection.

## B1 diagnostic repair and bounded controls

The blank-check label ambiguity is repaired in aaeb8db with fail-closed status separation. One old-profile control and one separate changed-profile preflight both passed their finite read-only readiness/auth401/full-log/stop checks. Offline build failures and corrected exact guest-parent provenance are retained. No kernel root cause or reliability acceptance follows; prior failures remain open. See ../boot-preflight-verification.md and normalized evidence/native-runtime/b1-verification.json.

## T7 single-boot staging observation

The separate changed B1 profile passed one fresh boot with two actual upload batches,12byte-readbacks and cooperative shutdown in14.85s. Full stopped serial-log audit has no recognized diagnostic or tested secret, with all isolation witnesses. It matches a separately disposable pinned reference after preserving two failed reference preparations. No native retry or default promotion; previous kernel/memory faults remain unresolved counter-evidence. See ../task-staging-runtime-verification.md.

## Release preview restart with a prepared authentication fixture

A signed CLI fixture prepared a fresh guest disk through the local setup API,
kept its session in memory, and stopped cleanly. The signed Release preview
then opened a private copy through Launch Services with cloud egress enabled.
On the first boot, the UI reported the configured 120-second readiness
timeout. The serial log eventually contained the ready marker and had a
131-second creation-to-final-write interval. File times approximate the
timeline and do not identify the slow stage or its cause.

Force stop recovered the UI. A second start of the same preview process and
state disk reached the normal login form. The second serial log had a
seven-second creation-to-final-write interval. No kernel panic marker was
observed on either boot. Preserve both results when evaluating reliability.
The provider model-list exercise is separate from startup acceptance.

## Cloud8 timeout candidate and fresh-disk controls

A signed timeout test on the one-vCPU cloud8 candidate panicked during
the blank-state disk check. The last stage before the fault was
`state_zero_check`, with no state format, mount or readiness marker.
The stack again includes `anon_vma_clone`, `__split_vma` and `munmap`.
After stopping the VM, a read-only host scan verified that all 2 GiB of
the retained synthetic disk were zero. The kernel hash matches the
earlier upload preflight that faulted on the same path.

Four prespecified, sequential fresh-disk preflights on that exact cloud8
manifest passed in 15–18 seconds. Each reached readiness, confirmed
fresh auth and a 401 on the protected API, and passed isolation and
cooperative-stop checks. The runtime PATH excluded Docker and the
Docker socket was deliberately unusable. Docker Desktop was running
for the separate browser baseline. The failure remains release
counter-evidence. The checker process was active at the fault, while
the cause of the invalid kernel memory access remains unresolved.
A controlled follow-up can vary only the checker implementation,
retaining full-device reads and fail-closed formatting decisions.
[Cloud8 boot evidence](../../evidence/native-runtime/cloud8-boot-control.json)

## Reusable blank-check buffer experiment

The alternative checker uses a single 1 MiB buffer and counts zero
bytes only in the range returned by each read. It scans through short
reads until EOF, rejects any nonzero data and treats an indeterminate
read as an execution failure. The block-device check and the init
format gate retain the same contract. Unit fixtures cover short reads
with nonzero data near the end and an indeterminate read.

The experiment rebuilt the cloud8 system disk from its pinned runtime
image with the checker as the only root filesystem file replaced. The
kernel, backend executable, init and package inventory matched the
control. The fixed sequence was control, reusable buffer, reusable
buffer, control. All four independent fresh-disk boots passed the
read-only auth, isolation and cooperative-stop preflight. Host
wall-clock times were 16, 11, 10 and 16 seconds. A separate local
regular-file sample traced about 2 MiB versus 1 MiB of peak Python
allocation. Those measurements do not establish guest kernel
allocation behavior, the cause of the panic, or release reliability.
The packaged preview still uses its previous guest.
[Experiment receipt](../../evidence/native-runtime/cloud8-blank-buffer.json)

The same reusable-buffer candidate passed the six-boot CLI lifecycle
suite. Five boots reached readiness. These covered first setup, one
normal restart and three forced-stop recoveries. The sixth boot
rejected the nonblank fixture before format. A read-only scan verified
its exact marker and zero remainder across 2 GiB. Auth, JWT and profile
persistence were observed on the same owned disk. Five API contract
groups matched a disposable fixed browser backend.

A separately signed Debug app bundled that same candidate and ran the
native diagnostics through Launch Services. First setup, login checks,
real Keychain restoration, temporary item removal and cooperative stop
during startup passed. Its LLM workflow matched eleven API contract
groups in a second disposable fixed browser backend. The app remained
a private fixture. Actual interaction and visual parity remain open.
[Lifecycle receipt](../../evidence/native-runtime/cloud8-blank-buffer-lifecycle.json)
